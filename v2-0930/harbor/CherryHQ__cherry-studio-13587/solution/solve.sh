#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/packages/shared/IpcChannel.ts b/packages/shared/IpcChannel.ts
--- a/packages/shared/IpcChannel.ts
+++ b/packages/shared/IpcChannel.ts
@@ -246,7 +246,7 @@ export enum IpcChannel {
   Backup_DeleteS3File = 'backup:deleteS3File',
   Backup_CheckS3Connection = 'backup:checkS3Connection',
   Backup_CreateLanTransferBackup = 'backup:createLanTransferBackup',
-  Backup_DeleteTempBackup = 'backup:deleteTempBackup',
+  Backup_DeleteLanTransferBackup = 'backup:deleteLanTransferBackup',
 
   // zip
   Zip_Compress = 'zip:compress',
diff --git a/src/main/index.ts b/src/main/index.ts
--- a/src/main/index.ts
+++ b/src/main/index.ts
@@ -149,7 +149,12 @@ if (!app.requestSingleInstanceLock()) {
       app.dock?.hide()
     }
 
+    // Check for backup restore marker and complete restoration (highest priority, before window creation)
+    const { BackupManager } = await import('./services/BackupManager')
+    await BackupManager.handleStartupRestore()
+
     const mainWindow = windowService.createMainWindow()
+
     new TrayService()
 
     // Setup macOS application menu
diff --git a/src/main/ipc.ts b/src/main/ipc.ts
--- a/src/main/ipc.ts
+++ b/src/main/ipc.ts
@@ -91,7 +91,7 @@ import { themeService } from './services/ThemeService'
 import VertexAIService from './services/VertexAIService'
 import { setOpenLinkExternal } from './services/WebviewService'
 import { windowService } from './services/WindowService'
-import { calculateDirectorySize, getDataPath, getResourcePath } from './utils'
+import { calculateDirectorySize, getResourcePath } from './utils'
 import { decrypt, encrypt } from './utils/aes'
 import {
   getCacheDir,
@@ -103,7 +103,6 @@ import {
   untildify
 } from './utils/file'
 import { updateAppDataConfig } from './utils/init'
-import { closeAllDataConnections } from './utils/lifecycle'
 import { getCpuName, getDeviceType, getHostname } from './utils/system'
 import { compress, decompress } from './utils/zip'
 
@@ -494,15 +493,7 @@ export async function registerIpc(mainWindow: BrowserWindow, app: Electron.App)
   })
 
   // Reset all data (factory reset)
-  // Best-effort: close handles then delete. Failures are logged but not thrown,
-  // because the caller must always proceed to relaunchApp() — process exit
-  // releases any remaining handles, and services auto-recreate on next start.
-  ipcMain.handle(IpcChannel.App_ResetData, async () => {
-    await closeAllDataConnections()
-    await fs.promises.rm(getDataPath(), { recursive: true, force: true }).catch((e) => {
-      logger.warn('Failed to remove Data directory (will be cleaned up on restart)', e as Error)
-    })
-  })
+  ipcMain.handle(IpcChannel.App_ResetData, () => backupManager.resetData())
 
   // check for update
   ipcMain.handle(IpcChannel.App_CheckForUpdate, async () => {
@@ -609,7 +600,7 @@ export async function registerIpc(mainWindow: BrowserWindow, app: Electron.App)
   ipcMain.handle(IpcChannel.Backup_DeleteS3File, backupManager.deleteS3File.bind(backupManager))
   ipcMain.handle(IpcChannel.Backup_CheckS3Connection, backupManager.checkS3Connection.bind(backupManager))
   ipcMain.handle(IpcChannel.Backup_CreateLanTransferBackup, backupManager.createLanTransferBackup.bind(backupManager))
-  ipcMain.handle(IpcChannel.Backup_DeleteTempBackup, backupManager.deleteTempBackup.bind(backupManager))
+  ipcMain.handle(IpcChannel.Backup_DeleteLanTransferBackup, backupManager.deleteLanTransferBackup.bind(backupManager))
 
   // file
   ipcMain.handle(IpcChannel.File_Open, fileManager.open.bind(fileManager))
diff --git a/src/main/services/BackupManager.ts b/src/main/services/BackupManager.ts
--- a/src/main/services/BackupManager.ts
+++ b/src/main/services/BackupManager.ts
@@ -15,19 +15,19 @@
  * --------------------------------------------------------------------------
  */
 import { loggerService } from '@logger'
+import { isWin } from '@main/constant'
 import { IpcChannel } from '@shared/IpcChannel'
 import type { WebDavConfig } from '@types'
 import type { S3Config } from '@types'
 import archiver from 'archiver'
-import { exec } from 'child_process'
 import { app } from 'electron'
 import * as fs from 'fs-extra'
 import StreamZip from 'node-stream-zip'
 import * as path from 'path'
 import type { CreateDirectoryOptions, FileStat } from 'webdav'
 
 import { getDataPath } from '../utils'
-import { closeAllDataConnections } from '../utils/lifecycle'
+import { resolveAndValidatePath } from '../utils/file'
 import S3Storage from './S3Storage'
 import WebDav from './WebDav'
 import { windowService } from './WindowService'
@@ -38,11 +38,11 @@ class BackupManager {
   private tempDir = path.join(app.getPath('temp'), 'cherry-studio', 'backup', 'temp')
   private backupDir = path.join(app.getPath('temp'), 'cherry-studio', 'backup')
 
-  // 缓存实例，避免重复创建
+  // Cached instance to avoid recreating
   private s3Storage: S3Storage | null = null
   private webdavInstance: WebDav | null = null
 
-  // 缓存核心连接配置，用于检测连接配置是否变更
+  // Cached core connection config, used to detect if connection config has changed
   private cachedS3ConnectionConfig: {
     endpoint: string
     region: string
@@ -59,177 +59,213 @@ class BackupManager {
     webdavPath?: string
   } | null = null
 
-  constructor() {
-    this.checkConnection = this.checkConnection.bind(this)
-    this.backup = this.backup.bind(this)
-    this.restore = this.restore.bind(this)
-    this.backupToWebdav = this.backupToWebdav.bind(this)
-    this.restoreFromWebdav = this.restoreFromWebdav.bind(this)
-    this.listWebdavFiles = this.listWebdavFiles.bind(this)
-    this.deleteWebdavFile = this.deleteWebdavFile.bind(this)
-    this.listLocalBackupFiles = this.listLocalBackupFiles.bind(this)
-    this.deleteLocalBackupFile = this.deleteLocalBackupFile.bind(this)
-    this.backupToLocalDir = this.backupToLocalDir.bind(this)
-    this.restoreFromLocalBackup = this.restoreFromLocalBackup.bind(this)
-    this.backupToS3 = this.backupToS3.bind(this)
-    this.restoreFromS3 = this.restoreFromS3.bind(this)
-    this.listS3Files = this.listS3Files.bind(this)
-    this.deleteS3File = this.deleteS3File.bind(this)
-    this.checkS3Connection = this.checkS3Connection.bind(this)
-  }
-
-  private async setWritableRecursive(dirPath: string): Promise<void> {
-    try {
-      const items = await fs.readdir(dirPath, { withFileTypes: true })
+  /**
+   * Handle backup restoration on app startup
+   * Called after window is created but before renderer is loaded
+   */
+  static async handleStartupRestore(): Promise<void> {
+    const userDataPath = app.getPath('userData')
 
-      for (const item of items) {
-        const fullPath = path.join(dirPath, item.name)
+    // Define restore paths
+    const indexedDBRestore = path.join(userDataPath, 'IndexedDB.restore')
+    const localStorageRestore = path.join(userDataPath, 'Local Storage.restore')
+    const dataRestore = getDataPath() + '.restore'
 
-        // 先处理子目录
-        if (item.isDirectory()) {
-          await this.setWritableRecursive(fullPath)
-        }
+    // Define target paths
+    const indexedDBDest = path.join(userDataPath, 'IndexedDB')
+    const localStorageDest = path.join(userDataPath, 'Local Storage')
+    const dataDest = getDataPath()
 
-        // 统一设置权限（Windows需要特殊处理）
-        await this.forceSetWritable(fullPath)
+    try {
+      // Check if any restore markers exist
+      const hasIndexedDBRestore = await fs.pathExists(indexedDBRestore)
+      const hasLocalStorageRestore = await fs.pathExists(localStorageRestore)
+      const hasDataRestore = await fs.pathExists(dataRestore)
+
+      // Restore IndexedDB
+      if (hasIndexedDBRestore) {
+        logger.info('[handleStartupRestore] Found IndexedDB.restore directories, completing restoration...')
+        await fs.remove(indexedDBDest).catch(() => {})
+        await fs.rename(indexedDBRestore, indexedDBDest)
       }
 
-      // 确保根目录权限
-      await this.forceSetWritable(dirPath)
-    } catch (error) {
-      logger.error(`权限设置失败：${dirPath}`, error as Error)
-      throw error
-    }
-  }
-
-  // 新增跨平台权限设置方法
-  private async forceSetWritable(targetPath: string): Promise<void> {
-    try {
-      // Windows系统需要先取消只读属性
-      if (process.platform === 'win32') {
-        await fs.chmod(targetPath, 0o666) // Windows会忽略权限位但能移除只读
-      } else {
-        const stats = await fs.stat(targetPath)
-        const mode = stats.isDirectory() ? 0o777 : 0o666
-        await fs.chmod(targetPath, mode)
+      // Restore Local Storage
+      if (hasLocalStorageRestore) {
+        logger.info('[handleStartupRestore] Found Local Storage.restore directories, completing restoration...')
+        await fs.remove(localStorageDest).catch(() => {})
+        await fs.rename(localStorageRestore, localStorageDest)
       }
 
-      // 双重保险：使用文件属性命令（Windows专用）
-      if (process.platform === 'win32') {
-        await exec(`attrib -R "${targetPath}" /L /D`)
+      // Restore Data
+      if (hasDataRestore) {
+        logger.info('[handleStartupRestore] Found Local Data.restore directories, completing restoration...')
+        await fs.remove(dataDest).catch(() => {})
+        await fs.rename(dataRestore, dataDest)
       }
+
+      logger.info('[handleStartupRestore] Restoration completed successfully')
     } catch (error) {
-      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
-        logger.warn(`权限设置警告：${targetPath}`, error as Error)
-      }
+      logger.error('[handleStartupRestore] Failed to complete restoration:', error as Error)
+      // Clean up restore markers to avoid endless retry loop
+      await fs.remove(indexedDBRestore).catch(() => {})
+      await fs.remove(localStorageRestore).catch(() => {})
+      await fs.remove(dataRestore).catch(() => {})
     }
   }
 
   /**
-   * 比较两个配置对象是否相等，只比较影响客户端连接的核心字段，忽略 fileName 等易变字段
+   * Backup metadata for direct backup format (version 6+)
    */
-  private isS3ConfigEqual(cachedConfig: typeof this.cachedS3ConnectionConfig, config: S3Config): boolean {
-    if (!cachedConfig) return false
-
-    return (
-      cachedConfig.endpoint === config.endpoint &&
-      cachedConfig.region === config.region &&
-      cachedConfig.bucket === config.bucket &&
-      cachedConfig.accessKeyId === config.accessKeyId &&
-      cachedConfig.secretAccessKey === config.secretAccessKey &&
-      cachedConfig.root === config.root
-    )
+  private createDirectBackupMetadata(): {
+    version: number
+    timestamp: number
+    appName: string
+    appVersion: string
+    platform: string
+    arch: string
+  } {
+    return {
+      version: 6,
+      timestamp: Date.now(),
+      appName: 'Cherry Studio',
+      appVersion: app.getVersion(),
+      platform: process.platform,
+      arch: process.arch
+    }
   }
 
   /**
-   * 深度比较两个 WebDAV 配置对象是否相等，只比较影响客户端连接的核心字段，忽略 fileName 等易变字段
+   * Direct backup method - copies IndexedDB and Local Storage directories directly.
+   * No JSON serialization, better performance for large databases.
+   * @param _ - Electron IPC event
+   * @param fileName - Name of the backup file
+   * @param destinationPath - Path to save the backup (defaults to this.backupDir)
+   * @param skipBackupFile - Whether to skip backing up the Data directory
+   * @returns Path to the created backup file
    */
-  private isWebDavConfigEqual(cachedConfig: typeof this.cachedWebdavConnectionConfig, config: WebDavConfig): boolean {
-    if (!cachedConfig) return false
+  async backup(
+    _: Electron.IpcMainInvokeEvent,
+    fileName: string,
+    destinationPath: string = this.backupDir,
+    skipBackupFile: boolean = false
+  ): Promise<string> {
+    const onProgress = this.onProgress(IpcChannel.BackupProgress, true)
 
-    return (
-      cachedConfig.webdavHost === config.webdavHost &&
-      cachedConfig.webdavUser === config.webdavUser &&
-      cachedConfig.webdavPass === config.webdavPass &&
-      cachedConfig.webdavPath === config.webdavPath
-    )
-  }
+    try {
+      await fs.ensureDir(this.tempDir)
+      onProgress({ stage: 'preparing', progress: 0, total: 100 })
 
-  /**
-   * 获取 S3Storage 实例，如果连接配置未变且实例已存在则复用，否则创建新实例
-   * 注意：只有连接相关的配置变更才会重新创建实例，其他配置变更不影响实例复用
-   */
-  private getS3Storage(config: S3Config): S3Storage {
-    // 检查核心连接配置是否变更
-    const configChanged = !this.isS3ConfigEqual(this.cachedS3ConnectionConfig, config)
+      const userDataPath = app.getPath('userData')
+      let currentProgress = 10
 
-    if (configChanged || !this.s3Storage) {
-      this.s3Storage = new S3Storage(config)
-      // 只缓存连接相关的配置字段
-      this.cachedS3ConnectionConfig = {
-        endpoint: config.endpoint,
-        region: config.region,
-        bucket: config.bucket,
-        accessKeyId: config.accessKeyId,
-        secretAccessKey: config.secretAccessKey,
-        root: config.root
+      // Step 2: Copy IndexedDB and Local Storage directories
+      onProgress({ stage: 'copying_database', progress: 15, total: 100 })
+      logger.debug('[backupDirect] Copying database directories...')
+
+      const indexedDBSource = path.join(userDataPath, 'IndexedDB')
+      const indexedDBDest = path.join(this.tempDir, 'IndexedDB')
+      if (await fs.pathExists(indexedDBSource)) {
+        await fs.copy(indexedDBSource, indexedDBDest)
+      } else {
+        logger.debug('[backupDirect] IndexedDB directory not found, skipping')
       }
-      logger.debug('[BackupManager] Created new S3Storage instance')
-    } else {
-      logger.debug('[BackupManager] Reusing existing S3Storage instance')
-    }
 
-    return this.s3Storage
-  }
+      const localStorageSource = path.join(userDataPath, 'Local Storage')
+      const localStorageDest = path.join(this.tempDir, 'Local Storage')
+      if (await fs.pathExists(localStorageSource)) {
+        await fs.copy(localStorageSource, localStorageDest)
+      } else {
+        logger.debug('[backupDirect] Local Storage directory not found, skipping')
+      }
 
-  /**
-   * 获取 WebDav 实例，如果连接配置未变且实例已存在则复用，否则创建新实例
-   * 注意：只有连接相关的配置变更才会重新创建实例，其他配置变更不影响实例复用
-   */
-  private getWebDavInstance(config: WebDavConfig): WebDav {
-    // 检查核心连接配置是否变更
-    const configChanged = !this.isWebDavConfigEqual(this.cachedWebdavConnectionConfig, config)
+      currentProgress = 50
+      onProgress({ stage: 'copying_database', progress: currentProgress, total: 100 })
 
-    if (configChanged || !this.webdavInstance) {
-      this.webdavInstance = new WebDav(config)
-      // 只缓存连接相关的配置字段
-      this.cachedWebdavConnectionConfig = {
-        webdavHost: config.webdavHost,
-        webdavUser: config.webdavUser,
-        webdavPass: config.webdavPass,
-        webdavPath: config.webdavPath
+      // Step 3: Write metadata.json
+      const metadata = this.createDirectBackupMetadata()
+      await fs.writeJson(path.join(this.tempDir, 'metadata.json'), metadata, { spaces: 2 })
+      onProgress({ stage: 'copying_database', progress: 52, total: 100 })
+
+      // Step 4: Copy Data directory (if not skipped)
+      if (!skipBackupFile) {
+        const sourcePath = path.join(userDataPath, 'Data')
+        const tempDataDir = path.join(this.tempDir, 'Data')
+
+        if (await fs.pathExists(sourcePath)) {
+          const totalSize = await this.getDirSize(sourcePath)
+          let copiedSize = 0
+
+          await this.copyDirWithProgress(sourcePath, tempDataDir, (size) => {
+            copiedSize += size
+            const progress = Math.min(80, 52 + Math.floor((copiedSize / totalSize) * 28))
+            onProgress({ stage: 'copying_files', progress, total: 100 })
+          })
+        }
+      } else {
+        logger.debug('[backupDirect] Skip the backup of the file')
+        await fs.promises.mkdir(path.join(this.tempDir, 'Data'))
       }
-      logger.debug('[BackupManager] Created new WebDav instance')
-    } else {
-      logger.debug('[BackupManager] Reusing existing WebDav instance')
-    }
+      onProgress({ stage: 'compressing', progress: 80, total: 100 })
 
-    return this.webdavInstance
+      // Step 5: Create ZIP archive
+      const backupedFilePath = path.join(destinationPath, fileName)
+      const output = fs.createWriteStream(backupedFilePath)
+      const archive = archiver('zip', {
+        zlib: { level: 0 }, // No compression - data is already compressed by LevelDB
+        zip64: true
+      })
+
+      await new Promise<void>((resolve, reject) => {
+        output.on('close', () => resolve())
+        archive.on('error', reject)
+        archive.on('warning', (err: any) => {
+          if (err.code !== 'ENOENT') {
+            logger.warn('[backupDirect] Archive warning:', err)
+          }
+        })
+        archive.pipe(output)
+        archive.directory(this.tempDir, false)
+        archive.finalize()
+      })
+
+      // Clean up temp directory
+      await fs.remove(this.tempDir)
+      onProgress({ stage: 'completed', progress: 100, total: 100 })
+
+      logger.info('[backupDirect] Backup completed successfully')
+      return backupedFilePath
+    } catch (error) {
+      logger.error('[backupDirect] Backup failed:', error as Error)
+      await fs.remove(this.tempDir).catch(() => {})
+
+      throw error
+    }
   }
 
-  async backup(
+  /**
+   * Legacy backup method (JSON format, used by LanTransfer)
+   * Creates a backup in the old format with data.json and optional Data directory.
+   * @param _ - Electron IPC event
+   * @param fileName - Name of the backup file
+   * @param data - JSON string data to backup
+   * @param destinationPath - Path to save the backup (defaults to this.backupDir)
+   * @param skipBackupFile - Whether to skip backing up the Data directory
+   * @returns Path to the created backup file
+   */
+  async backupLegacy(
     _: Electron.IpcMainInvokeEvent,
     fileName: string,
     data: string,
     destinationPath: string = this.backupDir,
     skipBackupFile: boolean = false
   ): Promise<string> {
-    const mainWindow = windowService.getMainWindow()
-
-    const onProgress = (processData: { stage: string; progress: number; total: number }) => {
-      mainWindow?.webContents.send(IpcChannel.BackupProgress, processData)
-      // 只在关键阶段记录日志：开始、结束和主要阶段转换点
-      const logStages = ['preparing', 'writing_data', 'preparing_compression', 'completed']
-      if (logStages.includes(processData.stage) || processData.progress === 100) {
-        logger.debug('backup progress', processData)
-      }
-    }
+    const onProgress = this.onProgress(IpcChannel.BackupProgress, true)
 
     try {
       await fs.ensureDir(this.tempDir)
       onProgress({ stage: 'preparing', progress: 0, total: 100 })
 
-      // 使用流的方式写入 data.json
+      // Write data.json using streaming
       const tempDataPath = path.join(this.tempDir, 'data.json')
 
       await new Promise<void>((resolve, reject) => {
@@ -246,36 +282,35 @@ class BackupManager {
       logger.debug(`BackupManager IPC, skipBackupFile: ${skipBackupFile}`)
 
       if (!skipBackupFile) {
-        // 复制 Data 目录到临时目录
+        // Copy Data directory to temp directory
         const sourcePath = path.join(app.getPath('userData'), 'Data')
         const tempDataDir = path.join(this.tempDir, 'Data')
 
-        // 获取源目录总大小
+        // Get total size of source directory
         const totalSize = await this.getDirSize(sourcePath)
         let copiedSize = 0
 
-        // 使用流式复制
+        // Use streaming copy
         await this.copyDirWithProgress(sourcePath, tempDataDir, (size) => {
           copiedSize += size
           const progress = Math.min(50, Math.floor((copiedSize / totalSize) * 50))
           onProgress({ stage: 'copying_files', progress, total: 100 })
         })
 
-        await this.setWritableRecursive(tempDataDir)
         onProgress({ stage: 'preparing_compression', progress: 50, total: 100 })
       } else {
         logger.debug('Skip the backup of the file')
-        await fs.promises.mkdir(path.join(this.tempDir, 'Data')) // 不创建空 Data 目录会导致 restore 失败
+        await fs.promises.mkdir(path.join(this.tempDir, 'Data')) // Creating empty Data dir is required, otherwise restore will fail
       }
 
-      // 创建输出文件流
+      // Create output file stream
       const backupedFilePath = path.join(destinationPath, fileName)
       const output = fs.createWriteStream(backupedFilePath)
 
-      // 创建 archiver 实例，启用 ZIP64 支持
+      // Create archiver instance, enable ZIP64 support
       const archive = archiver('zip', {
-        zlib: { level: 1 }, // 使用最低压缩级别以提高速度
-        zip64: true // 启用 ZIP64 支持以处理大文件
+        zlib: { level: 1 }, // Use lowest compression level for speed
+        zip64: true // Enable ZIP64 support for large files
       })
 
       let lastProgress = 50
@@ -284,7 +319,7 @@ class BackupManager {
       let totalBytes = 0
       let processedBytes = 0
 
-      // 首先计算总文件数和总大小，但不记录详细日志
+      // First calculate total files and size, but don't log details
       const calculateTotals = async (dirPath: string) => {
         try {
           const items = await fs.readdir(dirPath, { withFileTypes: true })
@@ -299,14 +334,14 @@ class BackupManager {
             }
           }
         } catch (error) {
-          // 仅在出错时记录日志
+          // Only log on error
           logger.error('[BackupManager] Error calculating totals:', error as Error)
         }
       }
 
       await calculateTotals(this.tempDir)
 
-      // 监听文件添加事件
+      // Listen for file entry events
       archive.on('entry', () => {
         processedEntries++
         if (totalEntries > 0) {
@@ -318,7 +353,7 @@ class BackupManager {
         }
       })
 
-      // 监听数据写入事件
+      // Listen for data write events
       archive.on('data', (chunk) => {
         processedBytes += chunk.length
         if (totalBytes > 0) {
@@ -330,7 +365,7 @@ class BackupManager {
         }
       })
 
-      // 使用 Promise 等待压缩完成
+      // Use Promise to wait for compression to complete
       await new Promise<void>((resolve, reject) => {
         output.on('close', () => {
           onProgress({ stage: 'compressing', progress: 100, total: 100 })
@@ -343,44 +378,131 @@ class BackupManager {
           }
         })
 
-        // 将输出流连接到压缩器
+        // Pipe output stream to archiver
         archive.pipe(output)
 
-        // 添加整个临时目录到压缩文件
+        // Add entire temp directory to archive
         archive.directory(this.tempDir, false)
 
-        // 完成压缩
+        // Finalize compression
         archive.finalize()
       })
 
-      // 清理临时目录
+      // Clean up temp directory
       await fs.remove(this.tempDir)
       onProgress({ stage: 'completed', progress: 100, total: 100 })
 
-      logger.debug('Backup completed successfully')
+      logger.info('Backup completed successfully')
       return backupedFilePath
     } catch (error) {
       logger.error('[BackupManager] Backup failed:', error as Error)
-      // 确保清理临时目录
+      // Ensure temp directory is cleaned up
       await fs.remove(this.tempDir).catch(() => {})
       throw error
     }
   }
 
-  async restore(_: Electron.IpcMainInvokeEvent, backupPath: string): Promise<string> {
-    const mainWindow = windowService.getMainWindow()
+  /**
+   * Direct backup to local directory
+   * Creates a backup and saves it to a local directory.
+   * @param _ - Electron IPC event
+   * @param fileName - Name of the backup file
+   * @param localConfig - Local backup configuration (directory path and options)
+   * @returns Path to the created backup file
+   */
+  async backupToLocalDir(
+    _: Electron.IpcMainInvokeEvent,
+    fileName: string,
+    localConfig: { localBackupDir?: string; skipBackupFile?: boolean }
+  ) {
+    try {
+      const backupDir = localConfig.localBackupDir || this.backupDir
+      await fs.ensureDir(backupDir)
+      return await this.backup(_, fileName, backupDir, localConfig.skipBackupFile)
+    } catch (error) {
+      logger.error('[backupToLocalDir] Local backup failed:', error as Error)
+      throw error
+    }
+  }
 
-    const onProgress = (processData: { stage: string; progress: number; total: number }) => {
-      mainWindow?.webContents.send(IpcChannel.RestoreProgress, processData)
-      // 只在关键阶段记录日志
-      const logStages = ['preparing', 'extracting', 'extracted', 'reading_data', 'completed']
-      if (logStages.includes(processData.stage) || processData.progress === 100) {
-        logger.debug('restore progress', processData)
+  /**
+   * Direct backup to WebDAV
+   * Creates a backup and uploads it to a WebDAV server.
+   * @param _ - Electron IPC event
+   * @param webdavConfig - WebDAV configuration including server URL, credentials, and options
+   * @returns Result from WebDAV upload operation
+   */
+  async backupToWebdav(_: Electron.IpcMainInvokeEvent, webdavConfig: WebDavConfig) {
+    const filename = webdavConfig.fileName || 'cherry-studio.backup.zip'
+    const backupedFilePath = await this.backup(_, filename, undefined, webdavConfig.skipBackupFile)
+    const webdavClient = this.getWebDavInstance(webdavConfig)
+    try {
+      let result
+      if (webdavConfig.disableStream) {
+        const fileContent = await fs.readFile(backupedFilePath)
+        result = await webdavClient.putFileContents(filename, fileContent, { overwrite: true })
+      } else {
+        const contentLength = (await fs.stat(backupedFilePath)).size
+        result = await webdavClient.putFileContents(filename, fs.createReadStream(backupedFilePath), {
+          overwrite: true,
+          contentLength
+        })
       }
+      await fs.remove(backupedFilePath)
+      return result
+    } catch (error) {
+      await fs.remove(backupedFilePath).catch(() => {})
+      throw error
+    }
+  }
+
+  /**
+   * Direct backup to S3
+   * Creates a backup and uploads it to an S3-compatible storage.
+   * @param _ - Electron IPC event
+   * @param s3Config - S3 configuration including endpoint, bucket, credentials, and options
+   * @returns Result from S3 upload operation
+   */
+  async backupToS3(_: Electron.IpcMainInvokeEvent, s3Config: S3Config) {
+    const os = require('os')
+    const deviceName = os.hostname ? os.hostname() : 'device'
+    const timestamp = new Date()
+      .toISOString()
+      .replace(/[-:T.Z]/g, '')
+      .slice(0, 14)
+    const filename = s3Config.fileName || `cherry-studio.backup.${deviceName}.${timestamp}.zip`
+
+    logger.debug(`[backupToS3] Starting S3 backup to ${filename}`)
+
+    const backupedFilePath = await this.backup(_, filename, undefined, s3Config.skipBackupFile)
+    const s3Client = this.getS3Storage(s3Config)
+    try {
+      const fileBuffer = await fs.promises.readFile(backupedFilePath)
+      const result = await s3Client.putFileContents(filename, fileBuffer)
+      await fs.remove(backupedFilePath)
+      logger.info(`S3 backup completed: ${filename}`)
+      return result
+    } catch (error) {
+      logger.error('[backupToS3] S3 backup failed:', error as Error)
+      await fs.remove(backupedFilePath)
+      throw error
     }
+  }
+
+  /**
+   * Restore from a backup file
+   * Automatically detects backup format (direct v6+ or legacy) and restores accordingly.
+   * For direct backup: replaces IndexedDB and Local Storage directories, then relaunches app.
+   * For legacy backup: restores data from data.json and Data directory.
+   * @param _ - Electron IPC event
+   * @param backupPath - Path to the backup ZIP file
+   * @returns For legacy backup: the data string from data.json. For direct backup: void (app will relaunch)
+   */
+  async restore(_: Electron.IpcMainInvokeEvent, backupPath: string): Promise<string | void> {
+    const onProgress = this.onProgress(IpcChannel.RestoreProgress, true)
 
     try {
-      // 创建临时目录
+      // Create temp directory
       await fs.ensureDir(this.tempDir)
       onProgress({ stage: 'preparing', progress: 0, total: 100 })
 
@@ -389,88 +511,221 @@ class BackupManager {
       const zip = new StreamZip.async({ file: backupPath })
       onProgress({ stage: 'extracting', progress: 15, total: 100 })
       await zip.extract(null, this.tempDir)
-      onProgress({ stage: 'extracted', progress: 25, total: 100 })
+      onProgress({ stage: 'extracted', progress: 20, total: 100 })
+
+      // Check for backup type: direct (version 6+) or legacy (version <= 5)
+      const metadataPath = path.join(this.tempDir, 'metadata.json')
+      const isDirectBackup = await fs.pathExists(metadataPath)
+
+      if (isDirectBackup) {
+        // Direct backup format (version 6+)
+        logger.debug('Detected direct backup format (version 6+)')
+        // Note: tempDir is NOT cleaned up here - restoreDirect will use and clean it
+        await this.restoreDirect()
+        // Direct restore doesn't return data - app needs to relaunch
+        return
+      }
 
-      logger.debug('step 2: read data.json')
-      // 读取 data.json
-      const dataPath = path.join(this.tempDir, 'data.json')
-      const data = await fs.readFile(dataPath, 'utf-8')
-      onProgress({ stage: 'reading_data', progress: 35, total: 100 })
+      // Legacy backup format (version <= 5)
+      logger.debug('Detected legacy backup format (version <= 5)')
+
+      const data = await this.restoreLegacy()
+
+      return data
+    } catch (error) {
+      logger.error('Restore failed:', error as Error)
+      await fs.remove(this.tempDir).catch(() => {})
+      throw error
+    }
+  }
+
+  /**
+   * Restore from direct backup format (version 6+)
+   * Directly replaces IndexedDB and Local Storage directories.
+   * On Windows, uses .restore suffix to avoid file lock issues - handled on next startup.
+   */
+  private async restoreDirect(): Promise<void> {
+    const onProgress = this.onProgress(IpcChannel.RestoreProgress, true)
+
+    try {
+      // Read and validate metadata
+      const metadataPath = path.join(this.tempDir, 'metadata.json')
+      const metadata = await fs.readJson(metadataPath)
+
+      // Validate appName to ensure backup is from Cherry Studio
+      if (metadata.appName !== 'Cherry Studio') {
+        throw new Error('This backup file is not from Cherry Studio and cannot be restored')
+      }
+
+      // Warn about cross-platform restore
+      if (metadata.platform && metadata.platform !== process.platform) {
+        logger.warn(
+          `[restoreDirect] Cross-platform restore: backup from ${metadata.platform}, current is ${process.platform}`
+        )
+      }
+
+      onProgress({ stage: 'validating', progress: 25, total: 100 })
+
+      onProgress({ stage: 'restoring_database', progress: 30, total: 100 })
+
+      const userDataPath = app.getPath('userData')
+
+      // Restore IndexedDB and Local Storage
+      // On Windows, use .restore suffix to avoid file lock issues - handled on next startup
+      // On macOS/Linux, use direct replacement
+      const restoreSuffix = isWin ? '.restore' : ''
+
+      // IndexedDB & Local Storage Path
+      const indexedDBSource = path.join(this.tempDir, 'IndexedDB')
+      const indexedDBDest = path.join(userDataPath, 'IndexedDB' + restoreSuffix)
+      const localStorageSource = path.join(this.tempDir, 'Local Storage')
+      const localStorageDest = path.join(userDataPath, 'Local Storage' + restoreSuffix)
 
-      logger.debug('step 3: restore Data directory')
-      // 恢复 Data 目录
-      const sourcePath = path.join(this.tempDir, 'Data')
-      const destPath = getDataPath()
+      logger.debug('[restoreDirect] Restoring database directories...')
 
-      const dataExists = await fs.pathExists(sourcePath)
-      const dataFiles = dataExists ? await fs.readdir(sourcePath) : []
+      // Windows: copy to .restore suffix directories (swap happens on next startup)
+      // macOS/Linux: copy directly to target directories
+      // Always remove target directory first to ensure clean overwrite
+      if (await fs.pathExists(indexedDBSource)) {
+        await fs.remove(indexedDBDest).catch(() => {})
+        await fs.copy(indexedDBSource, indexedDBDest)
+      }
+
+      if (await fs.pathExists(localStorageSource)) {
+        await fs.remove(localStorageDest).catch(() => {})
+        await fs.copy(localStorageSource, localStorageDest)
+      }
+
+      onProgress({ stage: 'restoring_database', progress: 65, total: 100 })
+
+      //  Restore Data directory
+      const dataSource = path.join(this.tempDir, 'Data')
+      const dataDest = path.join(getDataPath(), restoreSuffix)
+      const dataExists = await fs.pathExists(dataSource)
+      const dataFiles = dataExists ? await fs.readdir(dataSource) : []
 
       if (dataExists && dataFiles.length > 0) {
-        // 获取源目录总大小
-        const totalSize = await this.getDirSize(sourcePath)
-        let copiedSize = 0
+        logger.debug('[restoreDirect] Restoring Data directory...')
 
-        // Close all database connections and file watchers before removing Data directory.
-        // On Windows, open file handles prevent deletion (EBUSY).
-        await closeAllDataConnections()
+        const totalSize = await this.getDirSize(dataSource)
+        let copiedSize = 0
 
-        await this.setWritableRecursive(destPath)
-        await fs.remove(destPath)
+        await fs.remove(dataDest)
 
-        // 使用流式复制
-        await this.copyDirWithProgress(sourcePath, destPath, (size) => {
+        await this.copyDirWithProgress(dataSource, dataDest, (size) => {
           copiedSize += size
-          const progress = Math.min(85, 35 + Math.floor((copiedSize / totalSize) * 50))
-          onProgress({ stage: 'copying_files', progress, total: 100 })
+          const progress = Math.min(95, 65 + Math.floor((copiedSize / totalSize) * 30))
+          onProgress({ stage: 'restoring_data', progress, total: 100 })
         })
       } else {
-        logger.debug('skipBackupFile is true, skip restoring Data directory')
+        logger.debug('[restoreDirect] No Data directory to restore')
       }
 
-      logger.debug('step 4: clean up temp directory')
-      // 清理临时目录
-      await this.setWritableRecursive(this.tempDir)
+      // Clean up
       await fs.remove(this.tempDir)
       onProgress({ stage: 'completed', progress: 100, total: 100 })
 
-      logger.debug('step 5: Restore completed successfully')
+      logger.info('[restoreDirect] Restore completed successfully, relaunching app...')
 
-      return data
+      // Relaunch app to load restored data
+      app.relaunch()
+      app.exit(0)
     } catch (error) {
-      logger.error('Restore failed:', error as Error)
+      logger.error('[restoreDirect] Restore failed:', error as Error)
       await fs.remove(this.tempDir).catch(() => {})
       throw error
     }
   }
 
-  async backupToWebdav(_: Electron.IpcMainInvokeEvent, data: string, webdavConfig: WebDavConfig) {
-    const filename = webdavConfig.fileName || 'cherry-studio.backup.zip'
-    const backupedFilePath = await this.backup(_, filename, data, undefined, webdavConfig.skipBackupFile)
-    const webdavClient = this.getWebDavInstance(webdavConfig)
+  /**
+   * Restore from legacy backup format (version <= 5)
+   * Restores data from data.json and Data directory.
+   * @param onProgress - Callback function to report restore progress
+   * @returns The data string read from data.json
+   */
+  private async restoreLegacy(): Promise<string> {
+    const onProgress = this.onProgress(IpcChannel.RestoreProgress, false)
+
     try {
-      let result
-      if (webdavConfig.disableStream) {
-        const fileContent = await fs.readFile(backupedFilePath)
-        result = await webdavClient.putFileContents(filename, fileContent, {
-          overwrite: true
+      logger.debug('[restoreLegacy] read data.json')
+
+      // Read data.json
+      const dataPath = path.join(this.tempDir, 'data.json')
+      const data = await fs.readFile(dataPath, 'utf-8')
+      onProgress({ stage: 'reading_data', progress: 35, total: 100 })
+
+      logger.debug('[restoreLegacy] restore Data directory')
+
+      // Restore Data directory
+      const restoreSuffix = isWin ? '.restore' : ''
+      const dataSourcePath = path.join(this.tempDir, 'Data')
+      const dataDestPath = path.join(getDataPath(), restoreSuffix)
+
+      const dataExists = await fs.pathExists(dataSourcePath)
+      const dataFiles = dataExists ? await fs.readdir(dataSourcePath) : []
+
+      if (dataExists && dataFiles.length > 0) {
+        // Get total size of source directory
+        const dataTotalSize = await this.getDirSize(dataSourcePath)
+        let copiedSize = 0
+
+        await fs.remove(dataDestPath)
+
+        // Use streaming copy
+        await this.copyDirWithProgress(dataSourcePath, dataDestPath, (size) => {
+          copiedSize += size
+          const progress = Math.min(85, 35 + Math.floor((copiedSize / dataTotalSize) * 50))
+          onProgress({ stage: 'copying_files', progress, total: 100 })
         })
       } else {
-        const contentLength = (await fs.stat(backupedFilePath)).size
-        result = await webdavClient.putFileContents(filename, fs.createReadStream(backupedFilePath), {
-          overwrite: true,
-          contentLength
-        })
+        logger.debug('[restoreLegacy] skipBackupFile is true, skip restoring Data directory')
       }
 
-      await fs.remove(backupedFilePath)
-      return result
+      // Clean up temp directory
+      logger.debug('[restoreLegacy] clean up temp directory')
+      await fs.remove(this.tempDir)
+
+      onProgress({ stage: 'completed', progress: 100, total: 100 })
+
+      logger.info('[restoreLegacy] Restore completed successfully')
+
+      return data
     } catch (error) {
-      // 上传失败时也删除本地临时文件
-      await fs.remove(backupedFilePath).catch(() => {})
+      logger.error('[restoreLegacy] Restore failed:', error as Error)
+      await fs.remove(this.tempDir).catch(() => {})
       throw error
     }
   }
 
+  /**
+   * Restore from a local backup file
+   * @param _ - Electron IPC event
+   * @param fileName - Name of the backup file
+   * @param localBackupDir - Directory where the backup file is located
+   * @returns Result from restore operation
+   */
+  async restoreFromLocalBackup(_: Electron.IpcMainInvokeEvent, fileName: string, localBackupDir: string) {
+    try {
+      const backupPath = resolveAndValidatePath(localBackupDir, fileName)
+
+      if (!fs.existsSync(backupPath)) {
+        throw new Error(`Backup file not found: ${backupPath}`)
+      }
+
+      return await this.restore(_, backupPath)
+    } catch (error) {
+      logger.error('[BackupManager] Local restore failed:', error as Error)
+      throw error
+    }
+  }
+
+  /**
+   * Restore from a WebDAV backup
+   * Downloads the backup file from WebDAV server and restores it.
+   * @param _ - Electron IPC event
+   * @param webdavConfig - WebDAV configuration including server URL, credentials, and file name
+   * @returns Result from restore operation
+   */
   async restoreFromWebdav(_: Electron.IpcMainInvokeEvent, webdavConfig: WebDavConfig) {
     const filename = webdavConfig.fileName || 'cherry-studio.backup.zip'
     const webdavClient = this.getWebDavInstance(webdavConfig)
@@ -482,7 +737,7 @@ class BackupManager {
         fs.mkdirSync(this.backupDir, { recursive: true })
       }
 
-      // 使用流的方式写入文件
+      // Write file using streaming
       await new Promise<void>((resolve, reject) => {
         const writeStream = fs.createWriteStream(backupedFilePath)
         writeStream.write(retrievedFile as Buffer)
@@ -499,25 +754,65 @@ class BackupManager {
     }
   }
 
-  listWebdavFiles = async (_: Electron.IpcMainInvokeEvent, config: WebDavConfig) => {
+  /**
+   * Restore from an S3 backup
+   * Downloads the backup file from S3 storage and restores it.
+   * @param _ - Electron IPC event
+   * @param s3Config - S3 configuration including bucket, credentials, and file name
+   * @returns Result from restore operation
+   */
+  async restoreFromS3(_: Electron.IpcMainInvokeEvent, s3Config: S3Config) {
+    const filename = s3Config.fileName || 'cherry-studio.backup.zip'
+
+    logger.debug(`Starting restore from S3: ${filename}`)
+
+    const s3Client = this.getS3Storage(s3Config)
     try {
-      const client = this.getWebDavInstance(config)
-      const files = await client.getDirectoryContents()
+      const retrievedFile = await s3Client.getFileContents(filename)
+      const backupedFilePath = path.join(this.backupDir, filename)
+      if (!fs.existsSync(this.backupDir)) {
+        fs.mkdirSync(this.backupDir, { recursive: true })
+      }
+      await new Promise<void>((resolve, reject) => {
+        const writeStream = fs.createWriteStream(backupedFilePath)
+        writeStream.write(retrievedFile as Buffer)
+        writeStream.end()
+        writeStream.on('finish', () => resolve())
+        writeStream.on('error', (error) => reject(error))
+      })
 
-      return files
-        .filter((file: FileStat) => file.type === 'file' && file.basename.endsWith('.zip'))
-        .map((file: FileStat) => ({
-          fileName: file.basename,
-          modifiedTime: file.lastmod,
-          size: file.size
-        }))
-        .sort((a, b) => new Date(b.modifiedTime).getTime() - new Date(a.modifiedTime).getTime())
+      logger.info(`S3 restore file downloaded successfully: ${filename}`)
+      return await this.restore(_, backupedFilePath)
     } catch (error: any) {
-      logger.error('Failed to list WebDAV files:', error)
-      throw new Error(error.message || 'Failed to list backup files')
+      logger.error('[BackupManager] Failed to restore from S3:', error)
+      throw new Error(error.message || 'Failed to restore backup file')
     }
   }
 
+  // ==================== File Utility Methods ====================
+  // These are helper methods for file operations like size calculation,
+  // directory copying with progress, and permission management.
+
+  /**
+   * Create a progress callback that sends IPC message and optionally logs.
+   * copying_files stage is never logged as it generates too many logs.
+   */
+  private onProgress = (channel: IpcChannel, shouldLog: boolean) => {
+    return (processData: { stage: string; progress: number; total: number }) => {
+      const mainWindow = windowService.getMainWindow()
+      mainWindow?.webContents.send(channel, processData)
+      // Never log copying_files as it generates too many log entries
+      if (shouldLog && processData.stage !== 'copying_files') {
+        logger.info('Backup progress', processData)
+      }
+    }
+  }
+
+  /**
+   * Calculate total size of a directory recursively
+   * @param dirPath - Directory path to calculate size
+   * @returns Total size in bytes
+   */
   private async getDirSize(dirPath: string): Promise<number> {
     let size = 0
     const items = await fs.readdir(dirPath, { withFileTypes: true })
@@ -534,17 +829,111 @@ class BackupManager {
     return size
   }
 
+  /**
+   * Create a empty restore data path, it will be reset after app relaunch
+   */
+  public async resetData() {
+    if (!isWin) {
+      return await fs.remove(getDataPath()).catch(() => {})
+    }
+
+    const dataRestorePath = getDataPath() + '.restore'
+    await fs.remove(dataRestorePath).catch(() => {})
+    await fs.ensureDir(dataRestorePath)
+  }
+
+  /**
+   * Deep compare two WebDAV config objects for equality
+   * Only compares core fields that affect client connection, ignores volatile fields like fileName
+   * @param cachedConfig - The cached WebDAV configuration
+   * @param config - The new WebDAV configuration to compare
+   * @returns True if the configs are equal (connection-related fields only)
+   */
+  private isWebDavConfigEqual(cachedConfig: typeof this.cachedWebdavConnectionConfig, config: WebDavConfig): boolean {
+    if (!cachedConfig) return false
+
+    return (
+      cachedConfig.webdavHost === config.webdavHost &&
+      cachedConfig.webdavUser === config.webdavUser &&
+      cachedConfig.webdavPass === config.webdavPass &&
+      cachedConfig.webdavPath === config.webdavPath
+    )
+  }
+
+  /**
+   * Get WebDav instance, reuses existing instance if connection config hasn't changed
+   * Note: Only connection-related config changes will recreate the instance
+   * Other config changes don't affect instance reuse
+   * @param config - WebDAV configuration
+   * @returns WebDav instance
+   */
+  private getWebDavInstance(config: WebDavConfig): WebDav {
+    // Check if core connection config has changed
+    const configChanged = !this.isWebDavConfigEqual(this.cachedWebdavConnectionConfig, config)
+
+    if (configChanged || !this.webdavInstance) {
+      this.webdavInstance = new WebDav(config)
+      // Only cache connection-related config fields
+      this.cachedWebdavConnectionConfig = {
+        webdavHost: config.webdavHost,
+        webdavUser: config.webdavUser,
+        webdavPass: config.webdavPass,
+        webdavPath: config.webdavPath
+      }
+      logger.debug('[BackupManager] Created new WebDav instance')
+    } else {
+      logger.debug('[BackupManager] Reusing existing WebDav instance')
+    }
+
+    return this.webdavInstance
+  }
+
+  // ==================== WebDAV Methods ====================
+  // These methods handle backup operations with WebDAV servers.
+
+  /**
+   * List backup files on WebDAV server
+   * @param _ - Electron IPC event
+   * @param config - WebDAV configuration
+   * @returns Array of backup file info (name, modified time, size), sorted by newest first
+   */
+  listWebdavFiles = async (_: Electron.IpcMainInvokeEvent, config: WebDavConfig) => {
+    try {
+      const client = this.getWebDavInstance(config)
+      const files = await client.getDirectoryContents()
+
+      return files
+        .filter((file: FileStat) => file.type === 'file' && file.basename.endsWith('.zip'))
+        .map((file: FileStat) => ({
+          fileName: file.basename,
+          modifiedTime: file.lastmod,
+          size: file.size
+        }))
+        .sort((a, b) => new Date(b.modifiedTime).getTime() - new Date(a.modifiedTime).getTime())
+    } catch (error: any) {
+      logger.error('Failed to list WebDAV files:', error)
+      throw new Error(error.message || 'Failed to list backup files')
+    }
+  }
+
+  /**
+   * Copy directory with progress reporting
+   * Recursively copies files from source to destination while reporting progress
+   * @param source - Source directory path
+   * @param destination - Destination directory path
+   * @param onProgress - Callback function called with size of each copied file
+   */
   private async copyDirWithProgress(
     source: string,
     destination: string,
     onProgress: (size: number) => void
   ): Promise<void> {
-    // 先统计总文件数
+    // First count total files
     let totalFiles = 0
     let processedFiles = 0
     let lastProgressReported = 0
 
-    // 计算总文件数
+    // Calculate total file count
     const countFiles = async (dir: string): Promise<number> => {
       let count = 0
       const items = await fs.readdir(dir, { withFileTypes: true })
@@ -560,7 +949,7 @@ class BackupManager {
 
     totalFiles = await countFiles(source)
 
-    // 复制文件并更新进度
+    // Copy files and update progress
     const copyDir = async (src: string, dest: string): Promise<void> => {
       const items = await fs.readdir(src, { withFileTypes: true })
 
@@ -576,7 +965,7 @@ class BackupManager {
           await fs.copy(sourcePath, destPath)
           processedFiles++
 
-          // 只在进度变化超过5%时报告进度
+          // Only report progress when change exceeds 5%
           const currentProgress = Math.floor((processedFiles / totalFiles) * 100)
           if (currentProgress - lastProgressReported >= 5 || processedFiles === totalFiles) {
             lastProgressReported = currentProgress
@@ -589,11 +978,25 @@ class BackupManager {
     await copyDir(source, destination)
   }
 
+  /**
+   * Check WebDAV connection
+   * @param _ - Electron IPC event
+   * @param webdavConfig - WebDAV configuration to test
+   * @returns True if connection is successful
+   */
   async checkConnection(_: Electron.IpcMainInvokeEvent, webdavConfig: WebDavConfig) {
     const webdavClient = this.getWebDavInstance(webdavConfig)
     return await webdavClient.checkConnection()
   }
 
+  /**
+   * Create a directory on WebDAV server
+   * @param _ - Electron IPC event
+   * @param webdavConfig - WebDAV configuration
+   * @param path - Directory path to create
+   * @param options - Optional directory creation options
+   * @returns Result from WebDAV operation
+   */
   async createDirectory(
     _: Electron.IpcMainInvokeEvent,
     webdavConfig: WebDavConfig,
@@ -604,6 +1007,13 @@ class BackupManager {
     return await webdavClient.createDirectory(path, options)
   }
 
+  /**
+   * Delete a backup file from WebDAV server
+   * @param _ - Electron IPC event
+   * @param fileName - Name of the file to delete
+   * @param webdavConfig - WebDAV configuration
+   * @returns Result from WebDAV operation
+   */
   async deleteWebdavFile(_: Electron.IpcMainInvokeEvent, fileName: string, webdavConfig: WebDavConfig) {
     try {
       const webdavClient = this.getWebDavInstance(webdavConfig)
@@ -614,71 +1024,15 @@ class BackupManager {
     }
   }
 
-  async backupToLocalDir(
-    _: Electron.IpcMainInvokeEvent,
-    data: string,
-    fileName: string,
-    localConfig: {
-      localBackupDir: string
-      skipBackupFile: boolean
-    }
-  ) {
-    try {
-      const backupDir = localConfig.localBackupDir
-      // Create backup directory if it doesn't exist
-      await fs.ensureDir(backupDir)
-
-      const backupedFilePath = await this.backup(_, fileName, data, backupDir, localConfig.skipBackupFile)
-      return backupedFilePath
-    } catch (error) {
-      logger.error('[BackupManager] Local backup failed:', error as Error)
-      throw error
-    }
-  }
-
-  async backupToS3(_: Electron.IpcMainInvokeEvent, data: string, s3Config: S3Config) {
-    const os = require('os')
-    const deviceName = os.hostname ? os.hostname() : 'device'
-    const timestamp = new Date()
-      .toISOString()
-      .replace(/[-:T.Z]/g, '')
-      .slice(0, 14)
-    const filename = s3Config.fileName || `cherry-studio.backup.${deviceName}.${timestamp}.zip`
-
-    logger.debug(`Starting S3 backup to ${filename}`)
-
-    const backupedFilePath = await this.backup(_, filename, data, undefined, s3Config.skipBackupFile)
-    const s3Client = this.getS3Storage(s3Config)
-    try {
-      const fileBuffer = await fs.promises.readFile(backupedFilePath)
-      const result = await s3Client.putFileContents(filename, fileBuffer)
-      await fs.remove(backupedFilePath)
-
-      logger.debug(`S3 backup completed successfully: ${filename}`)
-      return result
-    } catch (error) {
-      logger.error(`[BackupManager] S3 backup failed:`, error as Error)
-      await fs.remove(backupedFilePath)
-      throw error
-    }
-  }
-
-  async restoreFromLocalBackup(_: Electron.IpcMainInvokeEvent, fileName: string, localBackupDir: string) {
-    try {
-      const backupDir = localBackupDir
-      const backupPath = path.join(backupDir, fileName)
-
-      if (!fs.existsSync(backupPath)) {
-        throw new Error(`Backup file not found: ${backupPath}`)
-      }
-
-      return await this.restore(_, backupPath)
-    } catch (error) {
-      logger.error('[BackupManager] Local restore failed:', error as Error)
-      throw error
-    }
-  }
+  // ==================== Local Backup Methods ====================
+  // These methods handle backup operations with local directories.
 
+  /**
+   * List backup files in a local directory
+   * @param _ - Electron IPC event
+   * @param localBackupDir - Directory to list backup files from
+   * @returns Array of backup file info (name, modified time, size), sorted by newest first
+   */
   async listLocalBackupFiles(_: Electron.IpcMainInvokeEvent, localBackupDir: string) {
     try {
       const files = await fs.readdir(localBackupDir)
@@ -705,9 +1059,16 @@ class BackupManager {
     }
   }
 
+  /**
+   * Delete a local backup file
+   * @param _ - Electron IPC event
+   * @param fileName - Name of the file to delete
+   * @param localBackupDir - Directory where the backup file is located
+   * @returns True if deletion was successful
+   */
   async deleteLocalBackupFile(_: Electron.IpcMainInvokeEvent, fileName: string, localBackupDir: string) {
     try {
-      const filePath = path.join(localBackupDir, fileName)
+      const filePath = resolveAndValidatePath(localBackupDir, fileName)
 
       if (!fs.existsSync(filePath)) {
         throw new Error(`Backup file not found: ${filePath}`)
@@ -721,100 +1082,45 @@ class BackupManager {
     }
   }
 
-  async restoreFromS3(_: Electron.IpcMainInvokeEvent, s3Config: S3Config) {
-    const filename = s3Config.fileName || 'cherry-studio.backup.zip'
-
-    logger.debug(`Starting restore from S3: ${filename}`)
-
-    const s3Client = this.getS3Storage(s3Config)
-    try {
-      const retrievedFile = await s3Client.getFileContents(filename)
-      const backupedFilePath = path.join(this.backupDir, filename)
-      if (!fs.existsSync(this.backupDir)) {
-        fs.mkdirSync(this.backupDir, { recursive: true })
-      }
-      await new Promise<void>((resolve, reject) => {
-        const writeStream = fs.createWriteStream(backupedFilePath)
-        writeStream.write(retrievedFile as Buffer)
-        writeStream.end()
-        writeStream.on('finish', () => resolve())
-        writeStream.on('error', (error) => reject(error))
-      })
-
-      logger.debug(`S3 restore file downloaded successfully: ${filename}`)
-      return await this.restore(_, backupedFilePath)
-    } catch (error: any) {
-      logger.error('[BackupManager] Failed to restore from S3:', error)
-      throw new Error(error.message || 'Failed to restore backup file')
-    }
-  }
-
-  listS3Files = async (_: Electron.IpcMainInvokeEvent, s3Config: S3Config) => {
-    try {
-      const s3Client = this.getS3Storage(s3Config)
-
-      const objects = await s3Client.listFiles()
-      const files = objects
-        .filter((obj) => obj.key.endsWith('.zip'))
-        .map((obj) => {
-          const segments = obj.key.split('/')
-          const fileName = segments[segments.length - 1]
-          return {
-            fileName,
-            modifiedTime: obj.lastModified || '',
-            size: obj.size
-          }
-        })
-
-      return files.sort((a, b) => new Date(b.modifiedTime).getTime() - new Date(a.modifiedTime).getTime())
-    } catch (error: any) {
-      logger.error('Failed to list S3 files:', error)
-      throw new Error(error.message || 'Failed to list backup files')
-    }
-  }
-
-  async deleteS3File(_: Electron.IpcMainInvokeEvent, fileName: string, s3Config: S3Config) {
-    try {
-      const s3Client = this.getS3Storage(s3Config)
-      return await s3Client.deleteFile(fileName)
-    } catch (error: any) {
-      logger.error('Failed to delete S3 file:', error)
-      throw new Error(error.message || 'Failed to delete backup file')
-    }
-  }
-
-  async checkS3Connection(_: Electron.IpcMainInvokeEvent, s3Config: S3Config) {
-    const s3Client = this.getS3Storage(s3Config)
-    return await s3Client.checkConnection()
-  }
+  // ==================== Legacy & Temp Methods ====================
+  // These methods are for legacy backup format and temporary file operations.
 
   /**
-   * Create a temporary backup for LAN transfer
+   * Create a legacy backup
    * Creates a lightweight backup (skipBackupFile=true) in the temp directory
    * Returns the path to the created ZIP file
+   * @param data - JSON string data to backup
+   * @param destinationPath - Path to save the backup
    */
-  async createLanTransferBackup(_: Electron.IpcMainInvokeEvent, data: string): Promise<string> {
+  async createLanTransferBackup(
+    _: Electron.IpcMainInvokeEvent,
+    data: string,
+    destinationPath?: string
+  ): Promise<string> {
     const timestamp = new Date()
       .toISOString()
       .replace(/[-:T.Z]/g, '')
-      .slice(0, 12)
+      .slice(0, 14)
+
     const fileName = `cherry-studio.${timestamp}.zip`
     const tempPath = path.join(app.getPath('temp'), 'cherry-studio', 'lan-transfer')
+    const targetPath = destinationPath || tempPath
 
     // Ensure temp directory exists
-    await fs.ensureDir(tempPath)
+    await fs.ensureDir(targetPath)
 
     // Create backup with skipBackupFile=true (no Data folder)
-    const backupedFilePath = await this.backup(_, fileName, data, tempPath, true)
+    const backupedFilePath = await this.backupLegacy(_, fileName, data, targetPath, true)
 
     logger.info(`[BackupManager] Created LAN transfer backup at: ${backupedFilePath}`)
+
     return backupedFilePath
   }
 
   /**
    * Delete a temporary backup file after LAN transfer completes
    */
-  async deleteTempBackup(_: Electron.IpcMainInvokeEvent, filePath: string): Promise<boolean> {
+  async deleteLanTransferBackup(_: Electron.IpcMainInvokeEvent, filePath: string): Promise<boolean> {
     try {
       // Security check: only allow deletion within temp directory
       const tempBase = path.normalize(path.join(app.getPath('temp'), 'cherry-studio', 'lan-transfer'))
@@ -837,6 +1143,119 @@ class BackupManager {
       return false
     }
   }
+
+  // ==================== S3 Methods ====================
+  // These methods handle backup operations with S3-compatible storage.
+
+  /**
+   * Get S3Storage instance, reuses existing instance if connection config hasn't changed
+   * Note: Only connection-related config changes will recreate the instance
+   * Other config changes don't affect instance reuse
+   * @param config - S3 configuration
+   * @returns S3Storage instance
+   */
+  private getS3Storage(config: S3Config): S3Storage {
+    // Check if core connection config has changed
+    const configChanged = !this.isS3ConfigEqual(this.cachedS3ConnectionConfig, config)
+
+    if (configChanged || !this.s3Storage) {
+      this.s3Storage = new S3Storage(config)
+      // Only cache connection-related config fields
+      this.cachedS3ConnectionConfig = {
+        endpoint: config.endpoint,
+        region: config.region,
+        bucket: config.bucket,
+        accessKeyId: config.accessKeyId,
+        secretAccessKey: config.secretAccessKey,
+        root: config.root
+      }
+      logger.debug('[BackupManager] Created new S3Storage instance')
+    } else {
+      logger.debug('[BackupManager] Reusing existing S3Storage instance')
+    }
+
+    return this.s3Storage
+  }
+
+  /**
+   * Compare two S3 config objects for equality
+   * Only compares core fields that affect client connection, ignores volatile fields like fileName
+   * @param cachedConfig - The cached S3 configuration
+   * @param config - The new S3 configuration to compare
+   * @returns True if the configs are equal (connection-related fields only)
+   */
+  private isS3ConfigEqual(cachedConfig: typeof this.cachedS3ConnectionConfig, config: S3Config): boolean {
+    if (!cachedConfig) return false
+
+    return (
+      cachedConfig.endpoint === config.endpoint &&
+      cachedConfig.region === config.region &&
+      cachedConfig.bucket === config.bucket &&
+      cachedConfig.accessKeyId === config.accessKeyId &&
+      cachedConfig.secretAccessKey === config.secretAccessKey &&
+      cachedConfig.root === config.root
+    )
+  }
+
+  /**
+   * Check S3 connection
+   * @param _ - Electron IPC event
+   * @param s3Config - S3 configuration to test
+   * @returns True if connection is successful
+   */
+  async checkS3Connection(_: Electron.IpcMainInvokeEvent, s3Config: S3Config) {
+    const s3Client = this.getS3Storage(s3Config)
+    return await s3Client.checkConnection()
+  }
+
+  /**
+   * List backup files in S3 storage
+   * @param _ - Electron IPC event
+   * @param s3Config - S3 configuration
+   * @returns Array of backup file info (name, modified time, size), sorted by newest first
+   */
+  listS3Files = async (_: Electron.IpcMainInvokeEvent, s3Config: S3Config) => {
+    try {
+      const s3Client = this.getS3Storage(s3Config)
+
+      const objects = await s3Client.listFiles()
+      const files = objects
+        .filter((obj) => obj.key.endsWith('.zip'))
+        .map((obj) => {
+          const segments = obj.key.split('/')
+          const fileName = segments[segments.length - 1]
+          return {
+            fileName,
+            modifiedTime: obj.lastModified || '',
+            size: obj.size
+          }
+        })
+
+      return files.sort((a, b) => new Date(b.modifiedTime).getTime() - new Date(a.modifiedTime).getTime())
+    } catch (error: any) {
+      logger.error('Failed to list S3 files:', error)
+      throw new Error(error.message || 'Failed to list backup files')
+    }
+  }
+
+  /**
+   * Delete a backup file from S3 storage
+   * @param _ - Electron IPC event
+   * @param fileName - Name of the file to delete
+   * @param s3Config - S3 configuration
+   * @returns Result from S3 operation
+   */
+  async deleteS3File(_: Electron.IpcMainInvokeEvent, fileName: string, s3Config: S3Config) {
+    try {
+      const s3Client = this.getS3Storage(s3Config)
+      return await s3Client.deleteFile(fileName)
+    } catch (error: any) {
+      logger.error('Failed to delete S3 file:', error)
+      throw new Error(error.message || 'Failed to delete backup file')
+    }
+  }
 }
 
+export { BackupManager }
+
 export default BackupManager
diff --git a/src/main/services/ConfigManager.ts b/src/main/services/ConfigManager.ts
--- a/src/main/services/ConfigManager.ts
+++ b/src/main/services/ConfigManager.ts
@@ -14,6 +14,9 @@
  * - v2 Refactor PR   : https://github.com/CherryHQ/cherry-studio/pull/10162
  * --------------------------------------------------------------------------
  */
+import fs from 'node:fs'
+import path from 'node:path'
+
 import type { UpgradeChannel } from '@shared/config/constant'
 import { defaultLanguage, ZOOM_SHORTCUTS } from '@shared/config/constant'
 import type { LanguageVarious, Shortcut } from '@types'
@@ -24,6 +27,28 @@ import { v4 as uuidv4 } from 'uuid'
 
 import { locales } from '../utils/locales'
 
+/**
+ * Migrate config.json from legacy location (userData/config.json)
+ * to new location (userData/Data/config.json) if needed.
+ * This ensures the config is included in backups.
+ * Note: Data directory must be created before calling this function.
+ */
+function migrateConfigToDataDir(dataDir: string) {
+  const userData = app.getPath('userData')
+  const legacyConfigPath = path.join(userData, 'config.json')
+  const newConfigPath = path.join(dataDir, 'config.json')
+
+  // If legacy config exists and new config doesn't, migrate it
+  if (fs.existsSync(legacyConfigPath) && !fs.existsSync(newConfigPath)) {
+    try {
+      fs.copyFileSync(legacyConfigPath, newConfigPath)
+      fs.unlinkSync(legacyConfigPath)
+    } catch {
+      // Migration failed, will continue using legacy location
+    }
+  }
+}
+
 export enum ConfigKeys {
   Language = 'language',
   Theme = 'theme',
@@ -58,7 +83,18 @@ export class ConfigManager {
   private subscribers: Map<string, Array<(newValue: any) => void>> = new Map()
 
   constructor() {
-    this.store = new Store()
+    // Store config in Data directory so it's included in backups
+    const dataDir = path.join(app.getPath('userData'), 'Data')
+
+    // Ensure Data directory exists before migration and store creation
+    if (!fs.existsSync(dataDir)) {
+      fs.mkdirSync(dataDir, { recursive: true })
+    }
+
+    // Migrate config from legacy location to Data directory
+    migrateConfigToDataDir(dataDir)
+
+    this.store = new Store({ cwd: dataDir })
   }
 
   getLanguage(): LanguageVarious {
diff --git a/src/main/utils/file.ts b/src/main/utils/file.ts
--- a/src/main/utils/file.ts
+++ b/src/main/utils/file.ts
@@ -30,6 +30,25 @@ function initFileTypeMap() {
 // 初始化映射表
 initFileTypeMap()
 
+/**
+ * Resolves a relative path against a base directory and validates it is within bounds.
+ * Prevents path traversal attacks (e.g., ../../../etc/passwd).
+ *
+ * @param baseDir - The base directory
+ * @param relativePath - The relative path (may contain '..')
+ * @returns The resolved absolute file path
+ * @throws Error if resolved path is outside base directory
+ */
+export function resolveAndValidatePath(baseDir: string, relativePath: string): string {
+  const resolvedBase = path.resolve(baseDir)
+  const resolvedPath = path.resolve(baseDir, relativePath)
+  const separator = resolvedBase.endsWith(path.sep) ? '' : path.sep
+  if (!resolvedPath.startsWith(resolvedBase + separator)) {
+    throw new Error('Invalid file path: path traversal detected')
+  }
+  return resolvedPath
+}
+
 export function untildify(pathWithTilde: string) {
   if (pathWithTilde.startsWith('~')) {
     const homeDirectory = os.homedir()
diff --git a/src/main/utils/lifecycle.ts b/src/main/utils/lifecycle.ts
deleted file mode 100644
--- a/src/main/utils/lifecycle.ts
+++ /dev/null
@@ -1,29 +0,0 @@
-import { loggerService } from '@logger'
-
-import { DatabaseManager } from '../services/agents/database/DatabaseManager'
-import { fileStorage } from '../services/FileStorage'
-import KnowledgeService from '../services/KnowledgeService'
-import MemoryService from '../services/memory/MemoryService'
-
-const logger = loggerService.withContext('Lifecycle')
-
-/**
- * Close all data-layer connections and file watchers.
- * Must be called before deleting or replacing the Data/ directory
- * to avoid EBUSY on Windows.
- */
-export async function closeAllDataConnections(): Promise<void> {
-  const results = await Promise.allSettled([
-    DatabaseManager.close(),
-    MemoryService.getInstance().close(),
-    KnowledgeService.closeAll(),
-    fileStorage.stopFileWatcher()
-  ])
-
-  const labels = ['DatabaseManager', 'MemoryService', 'KnowledgeService', 'FileWatcher']
-  for (let i = 0; i < results.length; i++) {
-    if (results[i].status === 'rejected') {
-      logger.warn(`Failed to close ${labels[i]}`, (results[i] as PromiseRejectedResult).reason as Error)
-    }
-  }
-}
diff --git a/src/preload/index.ts b/src/preload/index.ts
--- a/src/preload/index.ts
+++ b/src/preload/index.ts
@@ -171,11 +171,11 @@ const api = {
     decompress: (text: Buffer) => ipcRenderer.invoke(IpcChannel.Zip_Decompress, text)
   },
   backup: {
-    backup: (filename: string, content: string, path: string, skipBackupFile: boolean) =>
-      ipcRenderer.invoke(IpcChannel.Backup_Backup, filename, content, path, skipBackupFile),
     restore: (path: string) => ipcRenderer.invoke(IpcChannel.Backup_Restore, path),
-    backupToWebdav: (data: string, webdavConfig: WebDavConfig) =>
-      ipcRenderer.invoke(IpcChannel.Backup_BackupToWebdav, data, webdavConfig),
+    // Direct backup methods (copy IndexedDB/LocalStorage directories directly)
+    backup: (fileName: string, destinationPath: string, skipBackupFile: boolean) =>
+      ipcRenderer.invoke(IpcChannel.Backup_Backup, fileName, destinationPath, skipBackupFile),
+    backupToWebdav: (webdavConfig: WebDavConfig) => ipcRenderer.invoke(IpcChannel.Backup_BackupToWebdav, webdavConfig),
     restoreFromWebdav: (webdavConfig: WebDavConfig) =>
       ipcRenderer.invoke(IpcChannel.Backup_RestoreFromWebdav, webdavConfig),
     listWebdavFiles: (webdavConfig: WebDavConfig) =>
@@ -186,11 +186,8 @@ const api = {
       ipcRenderer.invoke(IpcChannel.Backup_CreateDirectory, webdavConfig, path, options),
     deleteWebdavFile: (fileName: string, webdavConfig: WebDavConfig) =>
       ipcRenderer.invoke(IpcChannel.Backup_DeleteWebdavFile, fileName, webdavConfig),
-    backupToLocalDir: (
-      data: string,
-      fileName: string,
-      localConfig: { localBackupDir?: string; skipBackupFile?: boolean }
-    ) => ipcRenderer.invoke(IpcChannel.Backup_BackupToLocalDir, data, fileName, localConfig),
+    backupToLocalDir: (fileName: string, localConfig: { localBackupDir?: string; skipBackupFile?: boolean }) =>
+      ipcRenderer.invoke(IpcChannel.Backup_BackupToLocalDir, fileName, localConfig),
     restoreFromLocalBackup: (fileName: string, localBackupDir?: string) =>
       ipcRenderer.invoke(IpcChannel.Backup_RestoreFromLocalBackup, fileName, localBackupDir),
     listLocalBackupFiles: (localBackupDir?: string) =>
@@ -199,17 +196,16 @@ const api = {
       ipcRenderer.invoke(IpcChannel.Backup_DeleteLocalBackupFile, fileName, localBackupDir),
     checkWebdavConnection: (webdavConfig: WebDavConfig) =>
       ipcRenderer.invoke(IpcChannel.Backup_CheckConnection, webdavConfig),
-
-    backupToS3: (data: string, s3Config: S3Config) => ipcRenderer.invoke(IpcChannel.Backup_BackupToS3, data, s3Config),
+    backupToS3: (s3Config: S3Config) => ipcRenderer.invoke(IpcChannel.Backup_BackupToS3, s3Config),
     restoreFromS3: (s3Config: S3Config) => ipcRenderer.invoke(IpcChannel.Backup_RestoreFromS3, s3Config),
     listS3Files: (s3Config: S3Config) => ipcRenderer.invoke(IpcChannel.Backup_ListS3Files, s3Config),
     deleteS3File: (fileName: string, s3Config: S3Config) =>
       ipcRenderer.invoke(IpcChannel.Backup_DeleteS3File, fileName, s3Config),
     checkS3Connection: (s3Config: S3Config) => ipcRenderer.invoke(IpcChannel.Backup_CheckS3Connection, s3Config),
-    createLanTransferBackup: (data: string): Promise<string> =>
-      ipcRenderer.invoke(IpcChannel.Backup_CreateLanTransferBackup, data),
-    deleteTempBackup: (filePath: string): Promise<boolean> =>
-      ipcRenderer.invoke(IpcChannel.Backup_DeleteTempBackup, filePath)
+    createLanTransferBackup: (data: string, destinationPath?: string): Promise<string> =>
+      ipcRenderer.invoke(IpcChannel.Backup_CreateLanTransferBackup, data, destinationPath),
+    deleteLanTransferBackup: (filePath: string): Promise<boolean> =>
+      ipcRenderer.invoke(IpcChannel.Backup_DeleteLanTransferBackup, filePath)
   },
   file: {
     select: (options?: OpenDialogOptions): Promise<FileMetadata[] | null> =>
diff --git a/src/renderer/src/components/Icons/SVGIcon.tsx b/src/renderer/src/components/Icons/SVGIcon.tsx
--- a/src/renderer/src/components/Icons/SVGIcon.tsx
+++ b/src/renderer/src/components/Icons/SVGIcon.tsx
@@ -500,3 +500,39 @@ export const ZedIcon = (props: SVGProps<SVGSVGElement>) => {
     </svg>
   )
 }
+
+//joplin icon needs to be updated into iconfont
+export const JoplinIcon = (props: SVGProps<SVGSVGElement>) => (
+  <svg
+    viewBox="0 0 24 24"
+    width="16"
+    height="16"
+    fill="var(--color-icon)"
+    xmlns="http://www.w3.org/2000/svg"
+    {...props}>
+    <path d="M20.97 0h-8.9a.15.15 0 00-.16.15v2.83c0 .1.08.17.18.17h1.22c.49 0 .89.38.93.86V17.4l-.01.36-.05.29-.04.13a2.06 2.06 0 01-.38.7l-.02.03a2.08 2.08 0 01-.37.34c-.5.35-1.17.5-1.92.43a4.66 4.66 0 01-2.67-1.22 3.96 3.96 0 01-1.34-2.42c-.1-.78.14-1.47.65-1.93l.07-.05c.37-.31.84-.5 1.39-.55a.09.09 0 00.01 0l.3-.01.35.01h.02a4.39 4.39 0 011.5.44c.15.08.17 0 .18-.06V9.63a.26.26 0 00-.2-.26 7.5 7.5 0 00-6.76 1.61 6.37 6.37 0 00-2.03 5.5 8.18 8.18 0 002.71 5.08A9.35 9.35 0 0011.81 24c1.88 0 3.62-.64 4.9-1.81a6.32 6.32 0 002.06-4.3l.01-10.86V4.08a.95.95 0 01.95-.93h1.22a.17.17 0 00.17-.17V.15a.15.15 0 00-.15-.15z" />
+  </svg>
+)
+
+export const SiyuanIcon = (props: SVGProps<SVGSVGElement>) => (
+  <svg
+    viewBox="0 0 1024 1024"
+    version="1.1"
+    xmlns="http://www.w3.org/2000/svg"
+    p-id="2962"
+    width="16"
+    height="16"
+    {...props}>
+    <path
+      d="M309.76 148.16a84.8 84.8 0 0 0-10.88 11.84S288 170.24 288 171.2s-6.72 4.8-6.72 6.72-3.52 1.92-2.88 2.88a12.48 12.48 0 0 0-6.4 6.4 121.28 121.28 0 0 0-20.8 19.2 456.64 456.64 0 0 1-37.76 37.12v2.88c0 2.88 0 0 0 0s-3.52 1.92-6.72 5.12c-8.64 9.28-19.84 20.48-28.16 28.16l-7.04 7.04-2.56 2.88a114.88 114.88 0 0 0-20.16 21.76 2.88 2.88 0 0 1-8 8.64l-1.6 1.6a99.52 99.52 0 0 0-19.52 18.88 21.44 21.44 0 0 0-6.4 5.44c-14.08 14.4-22.4 23.04-22.72 23.04l-9.28 8.96-8.96 8.96V887.04c0 1.28 3.2 2.56 6.72-1.92s3.52-3.84 4.16-3.84 0-1.6 0 0S163.84 800 219.84 744.64l38.4-38.08c16-16.32 29.12-29.76 28.8-30.4s6.72-4.16 5.76-5.76 5.44-3.2 5.44-5.12 23.68-23.04 23.04-26.56 0-115.52 0-252.16V138.56a128 128 0 0 0-11.84 10.88z m373.76 2.24a96 96 0 0 0-13.44 15.04s-33.92 32-76.48 74.56l-42.56 42.88L512 320v504.96s5.76-5.12 5.12-5.76a29.44 29.44 0 0 0 8.32-7.68c3.84-4.16 9.92-10.24 13.76-13.76l21.44-21.76 21.76-21.44c18.56-18.24 32-32 32-32l8.96-9.6a69.76 69.76 0 0 1 10.56-9.6s3.84-1.92 3.84-3.52 6.4-4.48 5.76-5.12 3.2-2.56 2.56-3.2 1.6 0 0 0 11.52-10.24 24-22.72l22.72-22.4v-256-251.84c0-0.96 0-2.24-15.36 11.84z"
+      fill="#cdcdcd"
+      p-id="2963"></path>
+    <path
+      d="M322.24 136h0c-1.6 0 0-0.64 0 0z m2.88 0v504.64l45.12 44.16c37.44 36.8 93.76 92.8 116.48 114.88l14.4 15.04a64 64 0 0 0 10.24 9.6V320l-4.8-4.48c-2.88-2.24-7.68-7.36-11.52-10.88l-42.24-41.92-20.8-21.12-16-14.4a76.48 76.48 0 0 1-7.36-7.04l-23.36-23.68-42.56-44.16c-15.04-15.04-16-16-17.6-14.72z m376 1.92V640l123.84 123.84c98.24 97.92 124.48 123.52 126.4 123.52h2.56V386.56l-124.8-124.8C760 192 704 136.96 704 136.96a3.52 3.52 0 0 0-1.6 2.56z"
+      fill="#707070"
+      p-id="2964"></path>
+    <path
+      d="M699.52 136.64V136z m-376.96 249.6V136.96s-0.32 50.56 0 249.28zM512 573.76v-127.04zM667.84 672l-6.72 7.36 7.04-7.04c6.72-6.08 7.68-7.36 6.72-7.36zM184 272.96v1.92l2.56-1.92c2.56-1.92 0-2.24 0-2.24a5.44 5.44 0 0 0-2.56 2.24zM141.76 314.88a2.24 2.24 0 0 0 1.92 0v-1.6z m483.2 399.04a71.36 71.36 0 0 0-8.96 10.24 69.76 69.76 0 0 0 10.56-9.6 56 56 0 0 0 8.96-10.24 73.28 73.28 0 0 0-10.56 9.6z m-448 75.52l-3.2 3.2 3.52-2.88 3.52-3.52s-2.56 0-5.44 3.2z m-97.92 96v1.92l2.88-1.92s1.92-2.24 0-2.24a6.72 6.72 0 0 0-4.48 2.88z"
+      p-id="2965"></path>
+  </svg>
+)
diff --git a/src/renderer/src/components/Popups/BackupPopup.tsx b/src/renderer/src/components/Popups/BackupPopup.tsx
--- a/src/renderer/src/components/Popups/BackupPopup.tsx
+++ b/src/renderer/src/components/Popups/BackupPopup.tsx
@@ -1,6 +1,6 @@
 import { loggerService } from '@logger'
 import { getBackupProgressLabel } from '@renderer/i18n/label'
-import { backup } from '@renderer/services/BackupService'
+import { backup, backupToLanTransfer } from '@renderer/services/BackupService'
 import store from '@renderer/store'
 import { IpcChannel } from '@shared/IpcChannel'
 import { Modal, Progress } from 'antd'
@@ -13,17 +13,18 @@ const logger = loggerService.withContext('BackupPopup')
 
 interface Props {
   resolve: (data: any) => void
+  backupType?: 'direct' | 'lan-transfer'
 }
 
-type ProgressStageType = 'reading_data' | 'preparing' | 'extracting' | 'extracted' | 'copying_files' | 'completed'
+type ProgressStageType = 'preparing' | 'copying_database' | 'copying_files' | 'compressing' | 'completed'
 
 interface ProgressData {
   stage: ProgressStageType
   progress: number
   total: number
 }
 
-const PopupContainer: React.FC<Props> = ({ resolve }) => {
+const PopupContainer: React.FC<Props> = ({ resolve, backupType = 'direct' }) => {
   const [open, setOpen] = useState(true)
   const [progressData, setProgressData] = useState<ProgressData>()
   const { t } = useTranslation()
@@ -40,8 +41,13 @@ const PopupContainer: React.FC<Props> = ({ resolve }) => {
   }, [])
 
   const onOk = async () => {
-    logger.debug(`skipBackupFile: ${skipBackupFile}`)
-    await backup(skipBackupFile)
+    logger.debug(`skipBackupFile: ${skipBackupFile}, backupType: ${backupType}`)
+
+    if (backupType === 'lan-transfer') {
+      await backupToLanTransfer()
+    } else {
+      await backup(skipBackupFile)
+    }
     setOpen(false)
   }
 
@@ -67,21 +73,26 @@ const PopupContainer: React.FC<Props> = ({ resolve }) => {
   BackupPopup.hide = onCancel
 
   const isDisabled = progressData ? progressData.stage !== 'completed' : false
+  const isLanTransferMode = backupType === 'lan-transfer'
+
+  const title = isLanTransferMode ? t('settings.data.export_to_phone.file.title') : t('backup.title')
+  const okText = isLanTransferMode ? t('settings.data.export_to_phone.file.button') : t('backup.confirm.button')
+  const content = isLanTransferMode ? t('settings.data.export_to_phone.file.content') : t('backup.content')
 
   return (
     <Modal
-      title={t('backup.title')}
+      title={title}
       open={open}
       onOk={onOk}
       onCancel={onCancel}
       afterClose={onClose}
       okButtonProps={{ disabled: isDisabled }}
       cancelButtonProps={{ disabled: isDisabled }}
-      okText={t('backup.confirm.button')}
+      okText={okText}
       maskClosable={false}
       transitionName="animation-move-down"
       centered>
-      {!progressData && <div>{t('backup.content')}</div>}
+      {!progressData && <div>{content}</div>}
       {progressData && (
         <div style={{ textAlign: 'center', padding: '20px 0' }}>
           <Progress percent={Math.floor(progressData.progress)} strokeColor="var(--color-primary)" />
@@ -99,10 +110,11 @@ export default class BackupPopup {
   static hide() {
     TopView.hide(TopViewKey)
   }
-  static show() {
+  static show(backupType: 'direct' | 'lan-transfer' = 'direct') {
     return new Promise<any>((resolve) => {
       TopView.show(
         <PopupContainer
+          backupType={backupType}
           resolve={(v) => {
             resolve(v)
             TopView.hide(TopViewKey)
diff --git a/src/renderer/src/components/Popups/LanTransferPopup/hook.ts b/src/renderer/src/components/Popups/LanTransferPopup/hook.ts
--- a/src/renderer/src/components/Popups/LanTransferPopup/hook.ts
+++ b/src/renderer/src/components/Popups/LanTransferPopup/hook.ts
@@ -241,7 +241,7 @@ export function useLanTransfer(): UseLanTransferReturn {
         // Step 4: Clean up temp file
         if (backupPath) {
           try {
-            await window.api.backup.deleteTempBackup(backupPath)
+            await window.api.backup.deleteLanTransferBackup(backupPath)
             logger.info('Cleaned up temporary backup file')
           } catch (cleanupError) {
             logger.warn('Failed to clean up temp backup', cleanupError as Error)
@@ -279,7 +279,7 @@ export function useLanTransfer(): UseLanTransferReturn {
     // Clean up temp backup if exists (use ref to get current value)
     if (tempBackupPathRef.current) {
       try {
-        await window.api.backup.deleteTempBackup(tempBackupPathRef.current)
+        await window.api.backup.deleteLanTransferBackup(tempBackupPathRef.current)
       } catch (error) {
         logger.warn('Failed to cleanup temp backup on close', error as Error)
       }
diff --git a/src/renderer/src/components/Popups/LanTransferPopup/popup.tsx b/src/renderer/src/components/Popups/LanTransferPopup/popup.tsx
--- a/src/renderer/src/components/Popups/LanTransferPopup/popup.tsx
+++ b/src/renderer/src/components/Popups/LanTransferPopup/popup.tsx
@@ -1,5 +1,5 @@
 import { Modal } from 'antd'
-import { TriangleAlert } from 'lucide-react'
+import { Smartphone } from 'lucide-react'
 import type { FC } from 'react'
 import { useMemo } from 'react'
 import { useTranslation } from 'react-i18next'
@@ -53,12 +53,9 @@ export const PopupContainer: FC<PopupContainerProps> = ({ resolve }) => {
         {/* Device List */}
         <div className="mt-2 flex flex-col gap-3">
           {lanDevices.length === 0 ? (
-            // Warning when no devices
-            <div className="flex w-full items-center gap-2.5 rounded-[10px] border border-[rgba(255,159,41,0.4)] border-dashed bg-[rgba(255,159,41,0.1)] px-3.5 py-3">
-              <TriangleAlert size={20} className="text-orange-400" />
-              <span className="flex-1 text-[#ff9f29] text-[13px] leading-[1.4]">
-                {t('settings.data.export_to_phone.lan.no_connection_warning')}
-              </span>
+            <div className="flex flex-col items-center justify-center gap-3 py-10 text-center">
+              <Smartphone size={60} color="var(--color-text-3)" />
+              <span>{t('settings.data.export_to_phone.lan.no_connection_warning')}</span>
             </div>
           ) : (
             // Device cards
diff --git a/src/renderer/src/i18n/label.ts b/src/renderer/src/i18n/label.ts
--- a/src/renderer/src/i18n/label.ts
+++ b/src/renderer/src/i18n/label.ts
@@ -110,9 +110,10 @@ export const getProviderLabel = (id: string): string => {
 const backupProgressKeyMap = {
   completed: 'backup.progress.completed',
   compressing: 'backup.progress.compressing',
+  copying_database: 'backup.progress.copying_database',
   copying_files: 'backup.progress.copying_files',
-  preparing_compression: 'backup.progress.preparing_compression',
   preparing: 'backup.progress.preparing',
+  preparing_compression: 'backup.progress.preparing_compression',
   title: 'backup.progress.title',
   writing_data: 'backup.progress.writing_data'
 } as const
@@ -128,7 +129,10 @@ const restoreProgressKeyMap = {
   extracting: 'restore.progress.extracting',
   preparing: 'restore.progress.preparing',
   reading_data: 'restore.progress.reading_data',
-  title: 'restore.progress.title'
+  restoring_data: 'restore.progress.restoring_data',
+  restoring_database: 'restore.progress.restoring_database',
+  title: 'restore.progress.title',
+  validating: 'restore.progress.validating'
 }
 
 export const getRestoreProgressLabel = (key: string): string => {
diff --git a/src/renderer/src/i18n/locales/en-us.json b/src/renderer/src/i18n/locales/en-us.json
--- a/src/renderer/src/i18n/locales/en-us.json
+++ b/src/renderer/src/i18n/locales/en-us.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "Backup completed",
       "compressing": "Compressing files...",
+      "copying_database": "Copying database...",
       "copying_files": "Copying files... {{progress}}%",
       "preparing": "Preparing backup...",
       "preparing_compression": "Preparing compression...",
@@ -3148,7 +3149,10 @@
       "extracting": "Extracting backup...",
       "preparing": "Preparing restore...",
       "reading_data": "Reading data...",
-      "title": "Restore Progress"
+      "restoring_data": "Restoring files...",
+      "restoring_database": "Restoring database...",
+      "title": "Restore Progress",
+      "validating": "Validating backup..."
     },
     "title": "Data Restore"
   },
@@ -3701,7 +3705,15 @@
           "button": "Select backup file"
         },
         "content": "Export some data, including chat logs and settings. Please note that the backup process may take some time. Thank you for your patience.",
+        "file": {
+          "button": "Export to file",
+          "content": "Export data as a backup file that can be imported on mobile via file.",
+          "export_failed": "Export failed",
+          "export_success": "Export successful",
+          "title": "Export as file"
+        },
         "lan": {
+          "button": "Start Transfer",
           "connected": "Connected",
           "connection_failed": "Connection failed",
           "content": "Please ensure your computer and phone are on the same network for LAN transfer.",
diff --git a/src/renderer/src/i18n/locales/zh-cn.json b/src/renderer/src/i18n/locales/zh-cn.json
--- a/src/renderer/src/i18n/locales/zh-cn.json
+++ b/src/renderer/src/i18n/locales/zh-cn.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "备份完成",
       "compressing": "压缩文件...",
+      "copying_database": "复制数据库...",
       "copying_files": "复制文件... {{progress}}%",
       "preparing": "准备备份...",
       "preparing_compression": "准备压缩...",
@@ -3148,7 +3149,10 @@
       "extracting": "解压备份...",
       "preparing": "准备恢复...",
       "reading_data": "读取数据...",
-      "title": "恢复进度"
+      "restoring_data": "恢复文件...",
+      "restoring_database": "恢复数据库...",
+      "title": "恢复进度",
+      "validating": "验证备份..."
     },
     "title": "数据恢复"
   },
@@ -3701,7 +3705,15 @@
           "button": "选择备份文件"
         },
         "content": "导出部分数据，包括聊天记录、设置。请注意，备份过程可能需要一些时间，感谢您的耐心等待。",
+        "file": {
+          "button": "导出到文件",
+          "content": "将数据导出为备份文件，可在手机上通过文件方式导入。",
+          "export_failed": "导出失败",
+          "export_success": "导出成功",
+          "title": "导出为文件"
+        },
         "lan": {
+          "button": "开始传输",
           "connected": "连接成功",
           "connection_failed": "连接失败",
           "content": "请确保电脑和手机处于同一网络以使用局域网传输。",
diff --git a/src/renderer/src/i18n/locales/zh-tw.json b/src/renderer/src/i18n/locales/zh-tw.json
--- a/src/renderer/src/i18n/locales/zh-tw.json
+++ b/src/renderer/src/i18n/locales/zh-tw.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "備份完成",
       "compressing": "壓縮檔案...",
+      "copying_database": "複製資料庫...",
       "copying_files": "複製檔案... {{progress}}%",
       "preparing": "準備備份...",
       "preparing_compression": "準備壓縮...",
@@ -3148,7 +3149,10 @@
       "extracting": "解開備份...",
       "preparing": "準備復原...",
       "reading_data": "讀取資料...",
-      "title": "復原進度"
+      "restoring_data": "復原檔案...",
+      "restoring_database": "復原資料庫...",
+      "title": "復原進度",
+      "validating": "驗證備份..."
     },
     "title": "資料復原"
   },
@@ -3701,7 +3705,15 @@
           "button": "選擇備份檔案"
         },
         "content": "匯出部分資料，包括聊天記錄與設定。請注意，備份過程可能需要一些時間，感謝耐心等候。",
+        "file": {
+          "button": "匯出至檔案",
+          "content": "將資料匯出為備份檔案，可透過檔案在行動裝置上匯入。",
+          "export_failed": "匯出失敗",
+          "export_success": "匯出成功",
+          "title": "匯出為檔案"
+        },
         "lan": {
+          "button": "開始傳輸",
           "connected": "已連線",
           "connection_failed": "連線失敗",
           "content": "請確保電腦和手機處於同一網路以使用區域網路傳輸。",
diff --git a/src/renderer/src/i18n/translate/de-de.json b/src/renderer/src/i18n/translate/de-de.json
--- a/src/renderer/src/i18n/translate/de-de.json
+++ b/src/renderer/src/i18n/translate/de-de.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "Backup abgeschlossen",
       "compressing": "Dateien werden komprimiert...",
+      "copying_database": "Datenbank wird kopiert...",
       "copying_files": "Dateien werden kopiert... {{progress}}%",
       "preparing": "Backup wird vorbereitet...",
       "preparing_compression": "Komprimierung wird vorbereitet...",
@@ -3148,7 +3149,10 @@
       "extracting": "Backup wird entpackt...",
       "preparing": "Wiederherstellung wird vorbereitet...",
       "reading_data": "Daten werden gelesen...",
-      "title": "Wiederherstellungsfortschritt"
+      "restoring_data": "Dateien werden wiederhergestellt...",
+      "restoring_database": "Datenbank wird wiederhergestellt...",
+      "title": "Wiederherstellungsfortschritt",
+      "validating": "Backup wird überprüft..."
     },
     "title": "Datenwiederherstellung"
   },
@@ -3701,7 +3705,15 @@
           "button": "Sicherungsdatei auswählen"
         },
         "content": "Exportieren Sie einige Daten, einschließlich Chat-Protokollen und Einstellungen. Bitte beachten Sie, dass der Sicherungsvorgang einige Zeit in Anspruch nehmen kann. Vielen Dank für Ihre Geduld.",
+        "file": {
+          "button": "In Datei exportieren",
+          "content": "Exportiere Daten als Sicherungsdatei, die per Datei auf dem Mobilgerät importiert werden kann.",
+          "export_failed": "Export fehlgeschlagen",
+          "export_success": "Export erfolgreich",
+          "title": "Als Datei exportieren"
+        },
         "lan": {
+          "button": "Übertragung starten",
           "connected": "Verbunden",
           "connection_failed": "Verbindung fehlgeschlagen",
           "content": "Bitte stelle sicher, dass sich dein Computer und dein Telefon im selben Netzwerk befinden, um eine LAN-Übertragung durchzuführen. Öffne die Cherry Studio App, um diesen QR-Code zu scannen.",
diff --git a/src/renderer/src/i18n/translate/el-gr.json b/src/renderer/src/i18n/translate/el-gr.json
--- a/src/renderer/src/i18n/translate/el-gr.json
+++ b/src/renderer/src/i18n/translate/el-gr.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "Η αντιγραφή ασφαλείας ολοκληρώθηκε",
       "compressing": "Συμπίεση αρχείων...",
+      "copying_database": "Αντιγραφή βάσης δεδομένων...",
       "copying_files": "Αντιγραφή αρχείων... {{progress}}%",
       "preparing": "Ετοιμασία αντιγράφου ασφαλείας...",
       "preparing_compression": "Ετοιμασία συμπίεσης...",
@@ -3148,7 +3149,10 @@
       "extracting": "Εξtraction της αντιγραφής...",
       "preparing": "Ήταν προετοιμασία για την αποκατάσταση...",
       "reading_data": "Ανάγνωση δεδομένων...",
-      "title": "Πρόοδος αποκατάστασης"
+      "restoring_data": "Επαναφορά αρχείων...",
+      "restoring_database": "Επαναφορά βάσης δεδομένων...",
+      "title": "Πρόοδος αποκατάστασης",
+      "validating": "Επικύρωση αντιγράφου ασφαλείας..."
     },
     "title": "Επαναφορά Δεδομένων"
   },
@@ -3701,7 +3705,15 @@
           "button": "Επιλέξτε αρχείο αντιγράφων ασφαλείας"
         },
         "content": "Εξαγωγή μέρους των δεδομένων, συμπεριλαμβανομένων των ιστορικών συνομιλιών και των ρυθμίσεων. Σημειώστε ότι η διαδικασία δημιουργίας αντιγράφων ασφαλείας ενδέχεται να διαρκέσει κάποιο χρονικό διάστημα, ευχαριστούμε για την υπομονή σας.",
+        "file": {
+          "button": "Εξαγωγή σε αρχείο",
+          "content": "Εξαγωγή δεδομένων ως αρχείο αντιγράφου ασφαλείας που μπορεί να εισαχθεί σε κινητό μέσω αρχείου.",
+          "export_failed": "Η εξαγωγή απέτυχε",
+          "export_success": "Η εξαγωγή ολοκληρώθηκε με επιτυχία",
+          "title": "Εξαγωγή ως αρχείο"
+        },
         "lan": {
+          "button": "Έναρξη μεταφοράς",
           "connected": "Συνδεδεμένος",
           "connection_failed": "Η σύνδεση απέτυχε",
           "content": "Βεβαιωθείτε ότι ο υπολογιστής και το κινητό βρίσκονται στο ίδιο δίκτυο για να χρησιμοποιήσετε τη μεταφορά LAN. Ανοίξτε την εφαρμογή Cherry Studio και σαρώστε αυτόν τον κωδικό QR.",
diff --git a/src/renderer/src/i18n/translate/es-es.json b/src/renderer/src/i18n/translate/es-es.json
--- a/src/renderer/src/i18n/translate/es-es.json
+++ b/src/renderer/src/i18n/translate/es-es.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "Copia de seguridad completada",
       "compressing": "Comprimiendo archivos...",
+      "copying_database": "Copiando base de datos...",
       "copying_files": "Copiando archivos... {{progress}}%",
       "preparing": "Preparando copia de seguridad...",
       "preparing_compression": "Preparando compresión...",
@@ -3148,7 +3149,10 @@
       "extracting": "Descomprimiendo la copia de seguridad...",
       "preparing": "Preparando la restauración...",
       "reading_data": "Leyendo datos...",
-      "title": "Progreso de Restauración"
+      "restoring_data": "Restaurando archivos...",
+      "restoring_database": "Restaurando base de datos...",
+      "title": "Progreso de Restauración",
+      "validating": "Validando copia de seguridad..."
     },
     "title": "Restauración de Datos"
   },
@@ -3701,7 +3705,15 @@
           "button": "Seleccionar archivo de copia de seguridad"
         },
         "content": "Exportar parte de los datos, incluidos los registros de chat y la configuración. Tenga en cuenta que el proceso de copia de seguridad puede tardar un tiempo; gracias por su paciencia.",
+        "file": {
+          "button": "Exportar a archivo",
+          "content": "Exportar datos como archivo de respaldo que puede ser importado en el móvil a través de un archivo.",
+          "export_failed": "Exportación fallida",
+          "export_success": "Exportación exitosa",
+          "title": "Exportar como archivo"
+        },
         "lan": {
+          "button": "Iniciar transferencia",
           "connected": "Conectado",
           "connection_failed": "Conexión fallida",
           "content": "Asegúrate de que el ordenador y el móvil estén en la misma red para usar la transferencia por LAN. Abre la aplicación Cherry Studio y escanea este código QR.",
diff --git a/src/renderer/src/i18n/translate/fr-fr.json b/src/renderer/src/i18n/translate/fr-fr.json
--- a/src/renderer/src/i18n/translate/fr-fr.json
+++ b/src/renderer/src/i18n/translate/fr-fr.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "Sauvegarde terminée",
       "compressing": "Compression des fichiers...",
+      "copying_database": "Copie de la base de données...",
       "copying_files": "Copie des fichiers... {{progress}}%",
       "preparing": "Préparation de la sauvegarde...",
       "preparing_compression": "Préparation de la compression...",
@@ -3148,7 +3149,10 @@
       "extracting": "Décompression de la sauvegarde...",
       "preparing": "Préparation de la restauration...",
       "reading_data": "Lecture des données...",
-      "title": "Progression de la restauration"
+      "restoring_data": "Restauration des fichiers...",
+      "restoring_database": "Restauration de la base de données...",
+      "title": "Progression de la restauration",
+      "validating": "Validation de la sauvegarde..."
     },
     "title": "Restauration des données"
   },
@@ -3701,7 +3705,15 @@
           "button": "Sélectionner le fichier de sauvegarde"
         },
         "content": "Exporter une partie des données, incluant les historiques de discussion et les paramètres. Veuillez noter que le processus de sauvegarde peut prendre un certain temps ; merci pour votre patience.",
+        "file": {
+          "button": "Exporter vers un fichier",
+          "content": "Exporter les données sous forme de fichier de sauvegarde qui peut être importé sur mobile via un fichier.",
+          "export_failed": "L'exportation a échoué",
+          "export_success": "Exportation réussie",
+          "title": "Exporter en tant que fichier"
+        },
         "lan": {
+          "button": "Démarrer le transfert",
           "connected": "Connecté",
           "connection_failed": "Échec de la connexion",
           "content": "Assurez-vous que l'ordinateur et le téléphone sont connectés au même réseau pour utiliser le transfert en réseau local. Ouvrez l'application Cherry Studio et scannez ce code QR.",
diff --git a/src/renderer/src/i18n/translate/ja-jp.json b/src/renderer/src/i18n/translate/ja-jp.json
--- a/src/renderer/src/i18n/translate/ja-jp.json
+++ b/src/renderer/src/i18n/translate/ja-jp.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "バックアップ完了",
       "compressing": "圧縮中...",
+      "copying_database": "データベースをコピー中...",
       "copying_files": "ファイルコピー中... {{progress}}%",
       "preparing": "バックアップ準備中...",
       "preparing_compression": "圧縮準備中...",
@@ -3148,7 +3149,10 @@
       "extracting": "バックアップ解凍中...",
       "preparing": "復元準備中...",
       "reading_data": "データ読み込み中...",
-      "title": "復元進捗"
+      "restoring_data": "ファイルを復元中...",
+      "restoring_database": "データベースを復元中...",
+      "title": "復元進捗",
+      "validating": "バックアップを検証中..."
     },
     "title": "データ復元"
   },
@@ -3701,7 +3705,15 @@
           "button": "バックアップファイルを選択"
         },
         "content": "一部のデータ、チャット履歴や設定をエクスポートします。バックアップには時間がかかる場合がありますので、しばらくお待ちください。",
+        "file": {
+          "button": "ファイルにエクスポート",
+          "content": "モバイルでファイル経由でインポートできるバックアップファイルとしてデータをエクスポートします。",
+          "export_failed": "エクスポートに失敗しました",
+          "export_success": "エクスポート成功",
+          "title": "ファイルとしてエクスポート"
+        },
         "lan": {
+          "button": "転送を開始",
           "connected": "接続済み",
           "connection_failed": "接続に失敗しました",
           "content": "コンピューターとスマートフォンが同じネットワークに接続されていることを確認し、ローカルエリアネットワーク転送を使用してください。Cherry Studioアプリを開き、このQRコードをスキャンしてください。",
diff --git a/src/renderer/src/i18n/translate/pt-pt.json b/src/renderer/src/i18n/translate/pt-pt.json
--- a/src/renderer/src/i18n/translate/pt-pt.json
+++ b/src/renderer/src/i18n/translate/pt-pt.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "Backup concluído",
       "compressing": "Comprimindo arquivo...",
+      "copying_database": "Copiando banco de dados...",
       "copying_files": "Copiando arquivos... {{progress}}%",
       "preparing": "Preparando backup...",
       "preparing_compression": "Preparando compressão...",
@@ -3148,7 +3149,10 @@
       "extracting": "Descompactando backup...",
       "preparing": "Preparando restauração...",
       "reading_data": "Lendo dados...",
-      "title": "Progresso da Restauração"
+      "restoring_data": "Restaurando arquivos...",
+      "restoring_database": "Restaurando banco de dados...",
+      "title": "Progresso da Restauração",
+      "validating": "Validando backup..."
     },
     "title": "Restauração de Dados"
   },
@@ -3701,7 +3705,15 @@
           "button": "Selecionar arquivo de backup"
         },
         "content": "Exportar parte dos dados, incluindo registros de conversas e configurações. Observe que o processo de backup pode demorar um pouco; agradecemos sua paciência.",
+        "file": {
+          "button": "Exportar para arquivo",
+          "content": "Exportar dados como arquivo de backup que pode ser importado no celular via arquivo.",
+          "export_failed": "Falha na exportação",
+          "export_success": "Exportação bem-sucedida",
+          "title": "Exportar como arquivo"
+        },
         "lan": {
+          "button": "Iniciar transferência",
           "connected": "Conectado",
           "connection_failed": "Falha na conexão",
           "content": "Certifique-se de que o computador e o telefone estejam na mesma rede para usar a transferência via LAN. Abra o aplicativo Cherry Studio e escaneie este código QR.",
diff --git a/src/renderer/src/i18n/translate/ro-ro.json b/src/renderer/src/i18n/translate/ro-ro.json
--- a/src/renderer/src/i18n/translate/ro-ro.json
+++ b/src/renderer/src/i18n/translate/ro-ro.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "Backup finalizat",
       "compressing": "Se comprimă fișierele...",
+      "copying_database": "Se copiază baza de date...",
       "copying_files": "Se copiază fișierele... {{progress}}%",
       "preparing": "Se pregătește backup-ul...",
       "preparing_compression": "Se pregătește compresia...",
@@ -3148,7 +3149,10 @@
       "extracting": "Se extrage backup-ul...",
       "preparing": "Se pregătește restaurarea...",
       "reading_data": "Se citesc datele...",
-      "title": "Progres restaurare"
+      "restoring_data": "Restaurare fișiere...",
+      "restoring_database": "Restaurare bază de date...",
+      "title": "Progres restaurare",
+      "validating": "Se validează copia de rezervă..."
     },
     "title": "Restaurare date"
   },
@@ -3701,7 +3705,15 @@
           "button": "Selectează fișierul de backup"
         },
         "content": "Exportă unele date, inclusiv jurnalele de chat și setările. Te rugăm să reții că procesul de backup poate dura ceva timp. Îți mulțumim pentru răbdare.",
+        "file": {
+          "button": "Exportă în fișier",
+          "content": "Exportă datele ca fișier de rezervă care poate fi importat pe mobil prin fișier.",
+          "export_failed": "Exportul a eșuat",
+          "export_success": "Export reușit",
+          "title": "Exportă ca fișier"
+        },
         "lan": {
+          "button": "Începe transferul",
           "connected": "Conectat",
           "connection_failed": "Conexiune eșuată",
           "content": "Te rugăm să te asiguri că computerul și telefonul sunt în aceeași rețea pentru transferul LAN.",
diff --git a/src/renderer/src/i18n/translate/ru-ru.json b/src/renderer/src/i18n/translate/ru-ru.json
--- a/src/renderer/src/i18n/translate/ru-ru.json
+++ b/src/renderer/src/i18n/translate/ru-ru.json
@@ -735,6 +735,7 @@
     "progress": {
       "completed": "Резервная копия создана",
       "compressing": "Сжатие файлов...",
+      "copying_database": "Копирование базы данных...",
       "copying_files": "Копирование файлов... {{progress}}%",
       "preparing": "Подготовка резервной копии...",
       "preparing_compression": "Подготовка сжатия...",
@@ -3148,7 +3149,10 @@
       "extracting": "Распаковка резервной копии...",
       "preparing": "Подготовка к восстановлению...",
       "reading_data": "Чтение данных...",
-      "title": "Прогресс восстановления"
+      "restoring_data": "Восстановление файлов...",
+      "restoring_database": "Восстановление базы данных...",
+      "title": "Прогресс восстановления",
+      "validating": "Проверка резервной копии..."
     },
     "title": "Восстановление данных"
   },
@@ -3701,7 +3705,15 @@
           "button": "Выберите файл резервной копии"
         },
         "content": "Экспорт части данных, включая историю чатов и настройки. Обратите внимание, процесс резервного копирования может занять некоторое время, благодарим за ваше терпение.",
+        "file": {
+          "button": "Экспорт в файл",
+          "content": "Экспортируйте данные как резервный файл, который можно импортировать на мобильное устройство через файл.",
+          "export_failed": "Экспорт не удался",
+          "export_success": "Экспорт выполнен успешно",
+          "title": "Экспортировать как файл"
+        },
         "lan": {
+          "button": "Начать передачу",
           "connected": "Подключено",
           "connection_failed": "Соединение не удалось",
           "content": "Убедитесь, что компьютер и телефон подключены к одной сети, чтобы использовать локальную передачу. Откройте приложение Cherry Studio и отсканируйте этот QR-код.",
diff --git a/src/renderer/src/pages/settings/DataSettings/BasicDataSettings.tsx b/src/renderer/src/pages/settings/DataSettings/BasicDataSettings.tsx
new file mode 100644
--- /dev/null
+++ b/src/renderer/src/pages/settings/DataSettings/BasicDataSettings.tsx
@@ -0,0 +1,627 @@
+import { LoadingOutlined, WifiOutlined } from '@ant-design/icons'
+import { HStack } from '@renderer/components/Layout'
+import BackupPopup from '@renderer/components/Popups/BackupPopup'
+import LanTransferPopup from '@renderer/components/Popups/LanTransferPopup'
+import RestorePopup from '@renderer/components/Popups/RestorePopup'
+import { useTheme } from '@renderer/context/ThemeProvider'
+import { useKnowledgeFiles } from '@renderer/hooks/useKnowledgeFiles'
+import { useTimer } from '@renderer/hooks/useTimer'
+import { reset } from '@renderer/services/BackupService'
+import store, { useAppDispatch } from '@renderer/store'
+import { setSkipBackupFile as _setSkipBackupFile } from '@renderer/store/settings'
+import type { AppInfo } from '@renderer/types'
+import { formatFileSize } from '@renderer/utils'
+import { occupiedDirs } from '@shared/config/constant'
+import { Button, Progress, Switch, Tooltip, Typography } from 'antd'
+import { FolderInput, FolderOpen, FolderOutput, SaveIcon } from 'lucide-react'
+import { useEffect, useState } from 'react'
+import { useTranslation } from 'react-i18next'
+import styled from 'styled-components'
+
+import { SettingDivider, SettingGroup, SettingHelpText, SettingRow, SettingRowTitle, SettingTitle } from '..'
+
+const BasicDataSettings: React.FC = () => {
+  const { t } = useTranslation()
+  const [appInfo, setAppInfo] = useState<AppInfo>()
+  const [cacheSize, setCacheSize] = useState<string>('')
+  const { size, removeAllFiles } = useKnowledgeFiles()
+  const { theme } = useTheme()
+  const { setTimeoutTimer } = useTimer()
+
+  const _skipBackupFile = store.getState().settings.skipBackupFile
+  const [skipBackupFile, setSkipBackupFile] = useState<boolean>(_skipBackupFile)
+
+  const dispatch = useAppDispatch()
+
+  useEffect(() => {
+    window.api.getAppInfo().then(setAppInfo)
+    window.api.getCacheSize().then(setCacheSize)
+  }, [])
+
+  const handleSelectAppDataPath = async () => {
+    if (!appInfo || !appInfo.appDataPath) {
+      return
+    }
+
+    const newAppDataPath = await window.api.select({
+      properties: ['openDirectory', 'createDirectory'],
+      title: t('settings.data.app_data.select_title')
+    })
+
+    if (!newAppDataPath) {
+      return
+    }
+
+    // check new app data path is root path
+    const pathParts = newAppDataPath.split(/[/\\]/).filter((part: string) => part !== '')
+    if (pathParts.length <= 1) {
+      window.toast.error(t('settings.data.app_data.select_error_root_path'))
+      return
+    }
+
+    // check new app data path is not in old app data path
+    const isInOldPath = await window.api.isPathInside(newAppDataPath, appInfo.appDataPath)
+    if (isInOldPath) {
+      window.toast.error(t('settings.data.app_data.select_error_same_path'))
+      return
+    }
+
+    // check new app data path is not in app install path
+    const isInInstallPath = await window.api.isPathInside(newAppDataPath, appInfo.installPath)
+    if (isInInstallPath) {
+      window.toast.error(t('settings.data.app_data.select_error_in_app_path'))
+      return
+    }
+
+    // check new app data path has write permission
+    const hasWritePermission = await window.api.hasWritePermission(newAppDataPath)
+    if (!hasWritePermission) {
+      window.toast.error(t('settings.data.app_data.select_error_write_permission'))
+      return
+    }
+
+    const migrationTitle = (
+      <div style={{ fontSize: '18px', fontWeight: 'bold' }}>{t('settings.data.app_data.migration_title')}</div>
+    )
+    const migrationClassName = 'migration-modal'
+    showMigrationConfirmModal(appInfo.appDataPath, newAppDataPath, migrationTitle, migrationClassName)
+  }
+
+  const doubleConfirmModalBeforeCopyData = (newPath: string) => {
+    window.modal.confirm({
+      title: t('settings.data.app_data.select_not_empty_dir'),
+      content: t('settings.data.app_data.select_not_empty_dir_content'),
+      centered: true,
+      okText: t('common.confirm'),
+      cancelText: t('common.cancel'),
+      onOk: () => {
+        window.toast.info({
+          title: t('settings.data.app_data.restart_notice'),
+          timeout: 2000
+        })
+        setTimeoutTimer(
+          'doubleConfirmModalBeforeCopyData',
+          () => {
+            window.api.relaunchApp({
+              args: ['--new-data-path=' + newPath]
+            })
+          },
+          500
+        )
+      }
+    })
+  }
+
+  // 显示确认迁移的对话框
+  const showMigrationConfirmModal = async (
+    originalPath: string,
+    newPath: string,
+    title: React.ReactNode,
+    className: string
+  ) => {
+    let shouldCopyData = !(await window.api.isNotEmptyDir(newPath))
+
+    const PathsContent = () => (
+      <div>
+        <MigrationPathRow>
+          <MigrationPathLabel>{t('settings.data.app_data.original_path')}:</MigrationPathLabel>
+          <MigrationPathValue>{originalPath}</MigrationPathValue>
+        </MigrationPathRow>
+        <MigrationPathRow style={{ marginTop: '16px' }}>
+          <MigrationPathLabel>{t('settings.data.app_data.new_path')}:</MigrationPathLabel>
+          <MigrationPathValue>{newPath}</MigrationPathValue>
+        </MigrationPathRow>
+      </div>
+    )
+
+    const CopyDataContent = () => (
+      <div>
+        <MigrationPathRow style={{ marginTop: '20px', flexDirection: 'row', alignItems: 'center' }}>
+          <Switch
+            defaultChecked={shouldCopyData}
+            onChange={(checked) => (shouldCopyData = checked)}
+            style={{ marginRight: '8px' }}
+            title={t('settings.data.app_data.copy_data_option')}
+          />
+          <MigrationPathLabel style={{ fontWeight: 'normal', fontSize: '14px' }}>
+            {t('settings.data.app_data.copy_data_option')}
+          </MigrationPathLabel>
+        </MigrationPathRow>
+      </div>
+    )
+
+    window.modal.confirm({
+      title,
+      className,
+      width: 'min(600px, 90vw)',
+      style: { minHeight: '400px' },
+      content: (
+        <MigrationModalContent>
+          <PathsContent />
+          <CopyDataContent />
+          <MigrationNotice>
+            <p style={{ color: 'var(--color-warning)' }}>{t('settings.data.app_data.restart_notice')}</p>
+            <p style={{ color: 'var(--color-text-3)', marginTop: '8px' }}>
+              {t('settings.data.app_data.copy_time_notice')}
+            </p>
+          </MigrationNotice>
+        </MigrationModalContent>
+      ),
+      centered: true,
+      okButtonProps: {
+        danger: true
+      },
+      okText: t('common.confirm'),
+      cancelText: t('common.cancel'),
+      onOk: async () => {
+        try {
+          if (shouldCopyData) {
+            if (await window.api.isNotEmptyDir(newPath)) {
+              doubleConfirmModalBeforeCopyData(newPath)
+              return
+            }
+
+            window.toast.info({
+              title: t('settings.data.app_data.restart_notice'),
+              timeout: 3000
+            })
+            setTimeoutTimer(
+              'showMigrationConfirmModal_1',
+              () => {
+                window.api.relaunchApp({
+                  args: ['--new-data-path=' + newPath]
+                })
+              },
+              500
+            )
+            return
+          }
+          await window.api.setAppDataPath(newPath)
+          window.toast.success(t('settings.data.app_data.path_changed_without_copy'))
+
+          setAppInfo(await window.api.getAppInfo())
+
+          setTimeoutTimer(
+            'showMigrationConfirmModal_2',
+            () => {
+              window.toast.success(t('settings.data.app_data.select_success'))
+              window.api.setStopQuitApp(false, '')
+              window.api.relaunchApp()
+            },
+            500
+          )
+        } catch (error) {
+          window.api.setStopQuitApp(false, '')
+          window.toast.error({
+            title: t('settings.data.app_data.path_change_failed') + ': ' + error,
+            timeout: 5000
+          })
+        }
+      }
+    })
+  }
+
+  // 显示进度模态框
+  const showProgressModal = (title: React.ReactNode, className: string, PathsContent: React.FC) => {
+    let currentProgress = 0
+    let progressInterval: NodeJS.Timeout | null = null
+
+    const loadingModal = window.modal.info({
+      title,
+      className,
+      width: 'min(600px, 90vw)',
+      style: { minHeight: '400px' },
+      icon: <LoadingOutlined style={{ fontSize: 18 }} />,
+      content: (
+        <MigrationModalContent>
+          <PathsContent />
+          <MigrationNotice>
+            <p>{t('settings.data.app_data.copying')}</p>
+            <div style={{ marginTop: '12px' }}>
+              <Progress percent={currentProgress} status="active" strokeWidth={8} />
+            </div>
+            <p style={{ color: 'var(--color-warning)', marginTop: '12px', fontSize: '13px' }}>
+              {t('settings.data.app_data.copying_warning')}
+            </p>
+          </MigrationNotice>
+        </MigrationModalContent>
+      ),
+      centered: true,
+      closable: false,
+      maskClosable: false,
+      okButtonProps: { style: { display: 'none' } }
+    })
+
+    const updateProgress = (progress: number, status: 'active' | 'success' = 'active') => {
+      loadingModal.update({
+        title,
+        content: (
+          <MigrationModalContent>
+            <PathsContent />
+            <MigrationNotice>
+              <p>{t('settings.data.app_data.copying')}</p>
+              <div style={{ marginTop: '12px' }}>
+                <Progress percent={Math.round(progress)} status={status} strokeWidth={8} />
+              </div>
+              <p style={{ color: 'var(--color-warning)', marginTop: '12px', fontSize: '13px' }}>
+                {t('settings.data.app_data.copying_warning')}
+              </p>
+            </MigrationNotice>
+          </MigrationModalContent>
+        )
+      })
+    }
+
+    progressInterval = setInterval(() => {
+      if (currentProgress < 95) {
+        currentProgress += Math.random() * 5 + 1
+        if (currentProgress > 95) currentProgress = 95
+        updateProgress(currentProgress)
+      }
+    }, 500)
+
+    return { loadingModal, progressInterval, updateProgress }
+  }
+
+  // 开始迁移数据
+  const startMigration = async (
+    originalPath: string,
+    newPath: string,
+    progressInterval: NodeJS.Timeout | null,
+    updateProgress: (progress: number, status?: 'active' | 'success') => void,
+    loadingModal: { destroy: () => void }
+  ): Promise<void> => {
+    await window.api.flushAppData()
+
+    await new Promise((resolve) => setTimeoutTimer('startMigration_1', resolve, 2000))
+
+    const copyResult = await window.api.copy(
+      originalPath,
+      newPath,
+      occupiedDirs.map((dir) => originalPath + '/' + dir)
+    )
+
+    if (progressInterval) {
+      clearInterval(progressInterval)
+    }
+
+    updateProgress(100, 'success')
+
+    if (!copyResult.success) {
+      await new Promise<void>((resolve) => {
+        setTimeoutTimer(
+          'startMigration_2',
+          () => {
+            loadingModal.destroy()
+            window.toast.error({
+              title: t('settings.data.app_data.copy_failed') + ': ' + copyResult.error,
+              timeout: 5000
+            })
+            resolve()
+          },
+          500
+        )
+      })
+
+      throw new Error(copyResult.error || 'Unknown error during copy')
+    }
+
+    await window.api.setAppDataPath(newPath)
+
+    await new Promise((resolve) => setTimeoutTimer('startMigration_3', resolve, 500))
+
+    loadingModal.destroy()
+
+    window.toast.success({
+      title: t('settings.data.app_data.copy_success'),
+      timeout: 2000
+    })
+  }
+
+  useEffect(() => {
+    const handleDataMigration = async () => {
+      const newDataPath = await window.api.getDataPathFromArgs()
+      if (!newDataPath) return
+
+      const originalPath = (await window.api.getAppInfo())?.appDataPath
+      if (!originalPath) return
+
+      const title = (
+        <div style={{ fontSize: '18px', fontWeight: 'bold' }}>{t('settings.data.app_data.migration_title')}</div>
+      )
+      const className = 'migration-modal'
+
+      const PathsContent = () => (
+        <div>
+          <MigrationPathRow>
+            <MigrationPathLabel>{t('settings.data.app_data.original_path')}:</MigrationPathLabel>
+            <MigrationPathValue>{originalPath}</MigrationPathValue>
+          </MigrationPathRow>
+          <MigrationPathRow style={{ marginTop: '16px' }}>
+            <MigrationPathLabel>{t('settings.data.app_data.new_path')}:</MigrationPathLabel>
+            <MigrationPathValue>{newDataPath}</MigrationPathValue>
+          </MigrationPathRow>
+        </div>
+      )
+
+      const { loadingModal, progressInterval, updateProgress } = showProgressModal(title, className, PathsContent)
+      try {
+        window.api.setStopQuitApp(true, t('settings.data.app_data.stop_quit_app_reason'))
+        await startMigration(originalPath, newDataPath, progressInterval, updateProgress, loadingModal)
+
+        setAppInfo(await window.api.getAppInfo())
+
+        setTimeoutTimer(
+          'handleDataMigration',
+          () => {
+            window.toast.success(t('settings.data.app_data.select_success'))
+            window.api.setStopQuitApp(false, '')
+            window.api.relaunchApp({
+              args: ['--user-data-dir=' + newDataPath]
+            })
+          },
+          1000
+        )
+      } catch (error) {
+        window.api.setStopQuitApp(false, '')
+        window.toast.error({
+          title: t('settings.data.app_data.copy_failed') + ': ' + error,
+          timeout: 5000
+        })
+      } finally {
+        if (progressInterval) {
+          clearInterval(progressInterval)
+        }
+        loadingModal.destroy()
+      }
+    }
+
+    handleDataMigration()
+    // eslint-disable-next-line react-hooks/exhaustive-deps
+  }, [])
+
+  const handleOpenPath = (path?: string) => {
+    if (!path) return
+    if (path?.endsWith('log')) {
+      const dirPath = path.split(/[/\\]/).slice(0, -1).join('/')
+      window.api.openPath(dirPath)
+    } else {
+      window.api.openPath(path)
+    }
+  }
+
+  const handleClearCache = () => {
+    window.modal.confirm({
+      title: t('settings.data.clear_cache.title'),
+      content: t('settings.data.clear_cache.confirm'),
+      okText: t('settings.data.clear_cache.button'),
+      centered: true,
+      okButtonProps: {
+        danger: true
+      },
+      onOk: async () => {
+        try {
+          await window.api.clearCache()
+          await window.api.trace.cleanLocalData()
+          await window.api.getCacheSize().then(setCacheSize)
+          window.toast.success(t('settings.data.clear_cache.success'))
+        } catch (error) {
+          window.toast.error(t('settings.data.clear_cache.error'))
+        }
+      }
+    })
+  }
+
+  const handleRemoveAllFiles = () => {
+    window.modal.confirm({
+      centered: true,
+      title: t('settings.data.app_knowledge.remove_all') + ` (${formatFileSize(size)}) `,
+      content: t('settings.data.app_knowledge.remove_all_confirm'),
+      onOk: async () => {
+        await removeAllFiles()
+        window.toast.success(t('settings.data.app_knowledge.remove_all_success'))
+      },
+      okText: t('common.delete'),
+      okButtonProps: {
+        danger: true
+      }
+    })
+  }
+
+  const onSkipBackupFilesChange = (value: boolean) => {
+    setSkipBackupFile(value)
+    dispatch(_setSkipBackupFile(value))
+  }
+
+  return (
+    <>
+      <SettingGroup theme={theme}>
+        <SettingTitle>{t('settings.data.title')}</SettingTitle>
+        <SettingDivider />
+        <SettingRow>
+          <SettingRowTitle>{t('settings.general.backup.title')}</SettingRowTitle>
+          <HStack gap="5px" justifyContent="space-between">
+            <Button onClick={() => BackupPopup.show()} icon={<SaveIcon size={14} />}>
+              {t('settings.general.backup.button')}
+            </Button>
+            <Button onClick={RestorePopup.show} icon={<FolderOpen size={14} />}>
+              {t('settings.general.restore.button')}
+            </Button>
+          </HStack>
+        </SettingRow>
+        <SettingDivider />
+        <SettingRow>
+          <SettingRowTitle>{t('settings.data.backup.skip_file_data_title')}</SettingRowTitle>
+          <Switch checked={skipBackupFile} onChange={onSkipBackupFilesChange} />
+        </SettingRow>
+        <SettingRow>
+          <SettingHelpText>{t('settings.data.backup.skip_file_data_help')}</SettingHelpText>
+        </SettingRow>
+      </SettingGroup>
+      <SettingGroup theme={theme}>
+        <SettingTitle>{t('settings.data.export_to_phone.title')}</SettingTitle>
+        <SettingDivider />
+        <SettingRow>
+          <SettingRowTitle>{t('settings.data.export_to_phone.lan.title')}</SettingRowTitle>
+          <HStack gap="5px" justifyContent="space-between">
+            <Button onClick={LanTransferPopup.show} icon={<WifiOutlined size={14} />}>
+              {t('settings.data.export_to_phone.lan.button')}
+            </Button>
+          </HStack>
+        </SettingRow>
+        <SettingDivider />
+        <SettingRow>
+          <SettingRowTitle>{t('settings.data.export_to_phone.file.title')}</SettingRowTitle>
+          <HStack gap="5px" justifyContent="space-between">
+            <Button onClick={() => BackupPopup.show('lan-transfer')} icon={<FolderInput size={14} />}>
+              {t('settings.data.export_to_phone.file.button')}
+            </Button>
+          </HStack>
+        </SettingRow>
+      </SettingGroup>
+      <SettingGroup theme={theme}>
+        <SettingTitle>{t('settings.data.data.title')}</SettingTitle>
+        <SettingDivider />
+        <SettingRow>
+          <SettingRowTitle>{t('settings.data.app_data.label')}</SettingRowTitle>
+          <PathRow>
+            <PathText style={{ color: 'var(--color-text-3)' }} onClick={() => handleOpenPath(appInfo?.appDataPath)}>
+              {appInfo?.appDataPath}
+            </PathText>
+            <Tooltip title={t('settings.data.app_data.select')}>
+              <FolderOutput onClick={handleSelectAppDataPath} style={{ cursor: 'pointer' }} size={16} />
+            </Tooltip>
+            <HStack gap="5px" style={{ marginLeft: '8px' }}>
+              <Button onClick={() => handleOpenPath(appInfo?.appDataPath)}>{t('settings.data.app_data.open')}</Button>
+            </HStack>
+          </PathRow>
+        </SettingRow>
+        <SettingDivider />
+        <SettingRow>
+          <SettingRowTitle>{t('settings.data.app_logs.label')}</SettingRowTitle>
+          <PathRow>
+            <PathText style={{ color: 'var(--color-text-3)' }} onClick={() => handleOpenPath(appInfo?.logsPath)}>
+              {appInfo?.logsPath}
+            </PathText>
+            <HStack gap="5px" style={{ marginLeft: '8px' }}>
+              <Button onClick={() => handleOpenPath(appInfo?.logsPath)}>{t('settings.data.app_logs.button')}</Button>
+            </HStack>
+          </PathRow>
+        </SettingRow>
+        <SettingDivider />
+        <SettingRow>
+          <SettingRowTitle>{t('settings.data.app_knowledge.label')}</SettingRowTitle>
+          <HStack alignItems="center" gap="5px">
+            <Button onClick={handleRemoveAllFiles}>{t('settings.data.app_knowledge.button.delete')}</Button>
+          </HStack>
+        </SettingRow>
+        <SettingDivider />
+        <SettingRow>
+          <SettingRowTitle>
+            {t('settings.data.clear_cache.title')}
+            {cacheSize && <CacheText>({cacheSize}MB)</CacheText>}
+          </SettingRowTitle>
+          <HStack gap="5px">
+            <Button onClick={handleClearCache}>{t('settings.data.clear_cache.button')}</Button>
+          </HStack>
+        </SettingRow>
+        <SettingDivider />
+        <SettingRow>
+          <SettingRowTitle>{t('settings.general.reset.title')}</SettingRowTitle>
+          <HStack gap="5px">
+            <Button onClick={reset} danger>
+              {t('settings.general.reset.title')}
+            </Button>
+          </HStack>
+        </SettingRow>
+      </SettingGroup>
+    </>
+  )
+}
+
+const CacheText = styled(Typography.Text)`
+  color: var(--color-text-3);
+  font-size: 12px;
+  margin-left: 5px;
+  line-height: 16px;
+  display: inline-block;
+  vertical-align: middle;
+  text-align: left;
+`
+
+const PathText = styled(Typography.Text)`
+  flex: 1;
+  min-width: 0;
+  overflow: hidden;
+  text-overflow: ellipsis;
+  white-space: nowrap;
+  display: inline-block;
+  vertical-align: middle;
+  text-align: right;
+  margin-left: 5px;
+  cursor: pointer
+`
+
+const PathRow = styled(HStack)`
+  min-width: 0;
+  flex: 1;
+  width: 0;
+  align-items: center;
+  gap: 5px;
+`
+
+// Add styled components for migration modal
+const MigrationModalContent = styled.div`
+  padding: 20px 0 10px;
+  display: flex;
+  flex-direction: column;
+`
+
+const MigrationNotice = styled.div`
+  margin-top: 24px;
+  font-size: 14px;
+`
+
+const MigrationPathRow = styled.div`
+  display: flex;
+  flex-direction: column;
+  gap: 5px;
+`
+
+const MigrationPathLabel = styled.div`
+  font-weight: 600;
+  font-size: 15px;
+  color: var(--color-text-1);
+`
+
+const MigrationPathValue = styled.div`
+  font-size: 14px;
+  color: var(--color-text-2);
+  background-color: var(--color-background-soft);
+  padding: 8px 12px;
+  border-radius: 4px;
+  word-break: break-all;
+  border: 1px solid var(--color-border);
+`
+
+export default BasicDataSettings
diff --git a/src/renderer/src/pages/settings/DataSettings/DataSettings.tsx b/src/renderer/src/pages/settings/DataSettings/DataSettings.tsx
--- a/src/renderer/src/pages/settings/DataSettings/DataSettings.tsx
+++ b/src/renderer/src/pages/settings/DataSettings/DataSettings.tsx
@@ -1,37 +1,19 @@
-import { CloudServerOutlined, CloudSyncOutlined, LoadingOutlined, WifiOutlined, YuqueOutlined } from '@ant-design/icons'
+import { CloudServerOutlined, CloudSyncOutlined, YuqueOutlined } from '@ant-design/icons'
 import DividerWithText from '@renderer/components/DividerWithText'
+import { JoplinIcon, SiyuanIcon } from '@renderer/components/Icons'
 import { NutstoreIcon } from '@renderer/components/Icons/NutstoreIcons'
 import { HStack } from '@renderer/components/Layout'
 import ListItem from '@renderer/components/ListItem'
-import BackupPopup from '@renderer/components/Popups/BackupPopup'
-import LanTransferPopup from '@renderer/components/Popups/LanTransferPopup'
-import RestorePopup from '@renderer/components/Popups/RestorePopup'
 import { useTheme } from '@renderer/context/ThemeProvider'
-import { useKnowledgeFiles } from '@renderer/hooks/useKnowledgeFiles'
-import { useTimer } from '@renderer/hooks/useTimer'
 import ImportMenuOptions from '@renderer/pages/settings/DataSettings/ImportMenuSettings'
-import { reset } from '@renderer/services/BackupService'
-import store, { useAppDispatch } from '@renderer/store'
-import { setSkipBackupFile as _setSkipBackupFile } from '@renderer/store/settings'
-import type { AppInfo } from '@renderer/types'
-import { formatFileSize } from '@renderer/utils'
-import { occupiedDirs } from '@shared/config/constant'
-import { Button, Progress, Switch, Tooltip, Typography } from 'antd'
-import { FileText, FolderCog, FolderInput, FolderOpen, FolderOutput, SaveIcon } from 'lucide-react'
+import { FileText, FolderCog, FolderInput, FolderOpen } from 'lucide-react'
 import type { FC } from 'react'
-import { useEffect, useState } from 'react'
+import { useState } from 'react'
 import { useTranslation } from 'react-i18next'
 import styled from 'styled-components'
 
-import {
-  SettingContainer,
-  SettingDivider,
-  SettingGroup,
-  SettingHelpText,
-  SettingRow,
-  SettingRowTitle,
-  SettingTitle
-} from '..'
+import { SettingContainer } from '..'
+import BasicDataSettings from './BasicDataSettings'
 import ExportMenuOptions from './ExportMenuSettings'
 import JoplinSettings from './JoplinSettings'
 import LocalBackupSettings from './LocalBackupSettings'
@@ -46,40 +28,8 @@ import YuqueSettings from './YuqueSettings'
 
 const DataSettings: FC = () => {
   const { t } = useTranslation()
-  const [appInfo, setAppInfo] = useState<AppInfo>()
-  const [cacheSize, setCacheSize] = useState<string>('')
-  const { size, removeAllFiles } = useKnowledgeFiles()
   const { theme } = useTheme()
   const [menu, setMenu] = useState<string>('data')
-  const { setTimeoutTimer } = useTimer()
-
-  const _skipBackupFile = store.getState().settings.skipBackupFile
-  const [skipBackupFile, setSkipBackupFile] = useState<boolean>(_skipBackupFile)
-
-  const dispatch = useAppDispatch()
-
-  //joplin icon needs to be updated into iconfont
-  const JoplinIcon = () => (
-    <svg viewBox="0 0 24 24" width="16" height="16" fill="var(--color-icon)" xmlns="http://www.w3.org/2000/svg">
-      <path d="M20.97 0h-8.9a.15.15 0 00-.16.15v2.83c0 .1.08.17.18.17h1.22c.49 0 .89.38.93.86V17.4l-.01.36-.05.29-.04.13a2.06 2.06 0 01-.38.7l-.02.03a2.08 2.08 0 01-.37.34c-.5.35-1.17.5-1.92.43a4.66 4.66 0 01-2.67-1.22 3.96 3.96 0 01-1.34-2.42c-.1-.78.14-1.47.65-1.93l.07-.05c.37-.31.84-.5 1.39-.55a.09.09 0 00.01 0l.3-.01.35.01h.02a4.39 4.39 0 011.5.44c.15.08.17 0 .18-.06V9.63a.26.26 0 00-.2-.26 7.5 7.5 0 00-6.76 1.61 6.37 6.37 0 00-2.03 5.5 8.18 8.18 0 002.71 5.08A9.35 9.35 0 0011.81 24c1.88 0 3.62-.64 4.9-1.81a6.32 6.32 0 002.06-4.3l.01-10.86V4.08a.95.95 0 01.95-.93h1.22a.17.17 0 00.17-.17V.15a.15.15 0 00-.15-.15z" />
-    </svg>
-  )
-
-  const SiyuanIcon = () => (
-    <svg viewBox="0 0 1024 1024" version="1.1" xmlns="http://www.w3.org/2000/svg" p-id="2962" width="16" height="16">
-      <path
-        d="M309.76 148.16a84.8 84.8 0 0 0-10.88 11.84S288 170.24 288 171.2s-6.72 4.8-6.72 6.72-3.52 1.92-2.88 2.88a12.48 12.48 0 0 0-6.4 6.4 121.28 121.28 0 0 0-20.8 19.2 456.64 456.64 0 0 1-37.76 37.12v2.88c0 2.88 0 0 0 0s-3.52 1.92-6.72 5.12c-8.64 9.28-19.84 20.48-28.16 28.16l-7.04 7.04-2.56 2.88a114.88 114.88 0 0 0-20.16 21.76 2.88 2.88 0 0 1-8 8.64l-1.6 1.6a99.52 99.52 0 0 0-19.52 18.88 21.44 21.44 0 0 0-6.4 5.44c-14.08 14.4-22.4 23.04-22.72 23.04l-9.28 8.96-8.96 8.96V887.04c0 1.28 3.2 2.56 6.72-1.92s3.52-3.84 4.16-3.84 0-1.6 0 0S163.84 800 219.84 744.64l38.4-38.08c16-16.32 29.12-29.76 28.8-30.4s6.72-4.16 5.76-5.76 5.44-3.2 5.44-5.12 23.68-23.04 23.04-26.56 0-115.52 0-252.16V138.56a128 128 0 0 0-11.84 10.88z m373.76 2.24a96 96 0 0 0-13.44 15.04s-33.92 32-76.48 74.56l-42.56 42.88L512 320v504.96s5.76-5.12 5.12-5.76a29.44 29.44 0 0 0 8.32-7.68c3.84-4.16 9.92-10.24 13.76-13.76l21.44-21.76 21.76-21.44c18.56-18.24 32-32 32-32l8.96-9.6a69.76 69.76 0 0 1 10.56-9.6s3.84-1.92 3.84-3.52 6.4-4.48 5.76-5.12 3.2-2.56 2.56-3.2 1.6 0 0 0 11.52-10.24 24-22.72l22.72-22.4v-256-251.84c0-0.96 0-2.24-15.36 11.84z"
-        fill="#cdcdcd"
-        p-id="2963"></path>
-      <path
-        d="M322.24 136h0c-1.6 0 0-0.64 0 0z m2.88 0v504.64l45.12 44.16c37.44 36.8 93.76 92.8 116.48 114.88l14.4 15.04a64 64 0 0 0 10.24 9.6V320l-4.8-4.48c-2.88-2.24-7.68-7.36-11.52-10.88l-42.24-41.92-20.8-21.12-16-14.4a76.48 76.48 0 0 1-7.36-7.04l-23.36-23.68-42.56-44.16c-15.04-15.04-16-16-17.6-14.72z m376 1.92V640l123.84 123.84c98.24 97.92 124.48 123.52 126.4 123.52h2.56V386.56l-124.8-124.8C760 192 704 136.96 704 136.96a3.52 3.52 0 0 0-1.6 2.56z"
-        fill="#707070"
-        p-id="2964"></path>
-      <path
-        d="M699.52 136.64V136z m-376.96 249.6V136.96s-0.32 50.56 0 249.28zM512 573.76v-127.04zM667.84 672l-6.72 7.36 7.04-7.04c6.72-6.08 7.68-7.36 6.72-7.36zM184 272.96v1.92l2.56-1.92c2.56-1.92 0-2.24 0-2.24a5.44 5.44 0 0 0-2.56 2.24zM141.76 314.88a2.24 2.24 0 0 0 1.92 0v-1.6z m483.2 399.04a71.36 71.36 0 0 0-8.96 10.24 69.76 69.76 0 0 0 10.56-9.6 56 56 0 0 0 8.96-10.24 73.28 73.28 0 0 0-10.56 9.6z m-448 75.52l-3.2 3.2 3.52-2.88 3.52-3.52s-2.56 0-5.44 3.2z m-97.92 96v1.92l2.88-1.92s1.92-2.24 0-2.24a6.72 6.72 0 0 0-4.48 2.88z"
-        p-id="2965"></path>
-    </svg>
-  )
 
   const menuItems = [
     { key: 'divider_0', isDivider: true, text: t('settings.data.divider.basic') },
@@ -131,449 +81,6 @@ const DataSettings: FC = () => {
     }
   ]
 
-  useEffect(() => {
-    window.api.getAppInfo().then(setAppInfo)
-    window.api.getCacheSize().then(setCacheSize)
-  }, [])
-
-  const handleOpenPath = (path?: string) => {
-    if (!path) return
-    if (path?.endsWith('log')) {
-      const dirPath = path.split(/[/\\]/).slice(0, -1).join('/')
-      window.api.openPath(dirPath)
-    } else {
-      window.api.openPath(path)
-    }
-  }
-
-  const handleClearCache = () => {
-    window.modal.confirm({
-      title: t('settings.data.clear_cache.title'),
-      content: t('settings.data.clear_cache.confirm'),
-      okText: t('settings.data.clear_cache.button'),
-      centered: true,
-      okButtonProps: {
-        danger: true
-      },
-      onOk: async () => {
-        try {
-          await window.api.clearCache()
-          await window.api.trace.cleanLocalData()
-          await window.api.getCacheSize().then(setCacheSize)
-          window.toast.success(t('settings.data.clear_cache.success'))
-        } catch (error) {
-          window.toast.error(t('settings.data.clear_cache.error'))
-        }
-      }
-    })
-  }
-
-  const handleRemoveAllFiles = () => {
-    window.modal.confirm({
-      centered: true,
-      title: t('settings.data.app_knowledge.remove_all') + ` (${formatFileSize(size)}) `,
-      content: t('settings.data.app_knowledge.remove_all_confirm'),
-      onOk: async () => {
-        await removeAllFiles()
-        window.toast.success(t('settings.data.app_knowledge.remove_all_success'))
-      },
-      okText: t('common.delete'),
-      okButtonProps: {
-        danger: true
-      }
-    })
-  }
-
-  const handleSelectAppDataPath = async () => {
-    if (!appInfo || !appInfo.appDataPath) {
-      return
-    }
-
-    const newAppDataPath = await window.api.select({
-      properties: ['openDirectory', 'createDirectory'],
-      title: t('settings.data.app_data.select_title')
-    })
-
-    if (!newAppDataPath) {
-      return
-    }
-
-    // check new app data path is root path
-    // if is root path, show error
-    const pathParts = newAppDataPath.split(/[/\\]/).filter((part: string) => part !== '')
-    if (pathParts.length <= 1) {
-      window.toast.error(t('settings.data.app_data.select_error_root_path'))
-      return
-    }
-
-    // check new app data path is not in old app data path
-    const isInOldPath = await window.api.isPathInside(newAppDataPath, appInfo.appDataPath)
-    if (isInOldPath) {
-      window.toast.error(t('settings.data.app_data.select_error_same_path'))
-      return
-    }
-
-    // check new app data path is not in app install path
-    const isInInstallPath = await window.api.isPathInside(newAppDataPath, appInfo.installPath)
-    if (isInInstallPath) {
-      window.toast.error(t('settings.data.app_data.select_error_in_app_path'))
-      return
-    }
-
-    // check new app data path has write permission
-    const hasWritePermission = await window.api.hasWritePermission(newAppDataPath)
-    if (!hasWritePermission) {
-      window.toast.error(t('settings.data.app_data.select_error_write_permission'))
-      return
-    }
-
-    const migrationTitle = (
-      <div style={{ fontSize: '18px', fontWeight: 'bold' }}>{t('settings.data.app_data.migration_title')}</div>
-    )
-    const migrationClassName = 'migration-modal'
-    showMigrationConfirmModal(appInfo.appDataPath, newAppDataPath, migrationTitle, migrationClassName)
-  }
-
-  const doubleConfirmModalBeforeCopyData = (newPath: string) => {
-    window.modal.confirm({
-      title: t('settings.data.app_data.select_not_empty_dir'),
-      content: t('settings.data.app_data.select_not_empty_dir_content'),
-      centered: true,
-      okText: t('common.confirm'),
-      cancelText: t('common.cancel'),
-      onOk: () => {
-        window.toast.info({
-          title: t('settings.data.app_data.restart_notice'),
-          timeout: 2000
-        })
-        setTimeoutTimer(
-          'doubleConfirmModalBeforeCopyData',
-          () => {
-            window.api.relaunchApp({
-              args: ['--new-data-path=' + newPath]
-            })
-          },
-          500
-        )
-      }
-    })
-  }
-
-  // 显示确认迁移的对话框
-  const showMigrationConfirmModal = async (
-    originalPath: string,
-    newPath: string,
-    title: React.ReactNode,
-    className: string
-  ) => {
-    // 复制数据选项状态
-    let shouldCopyData = !(await window.api.isNotEmptyDir(newPath))
-
-    // 创建路径内容组件
-    const PathsContent = () => (
-      <div>
-        <MigrationPathRow>
-          <MigrationPathLabel>{t('settings.data.app_data.original_path')}:</MigrationPathLabel>
-          <MigrationPathValue>{originalPath}</MigrationPathValue>
-        </MigrationPathRow>
-        <MigrationPathRow style={{ marginTop: '16px' }}>
-          <MigrationPathLabel>{t('settings.data.app_data.new_path')}:</MigrationPathLabel>
-          <MigrationPathValue>{newPath}</MigrationPathValue>
-        </MigrationPathRow>
-      </div>
-    )
-
-    const CopyDataContent = () => (
-      <div>
-        <MigrationPathRow style={{ marginTop: '20px', flexDirection: 'row', alignItems: 'center' }}>
-          <Switch
-            defaultChecked={shouldCopyData}
-            onChange={(checked) => (shouldCopyData = checked)}
-            style={{ marginRight: '8px' }}
-            title={t('settings.data.app_data.copy_data_option')}
-          />
-          <MigrationPathLabel style={{ fontWeight: 'normal', fontSize: '14px' }}>
-            {t('settings.data.app_data.copy_data_option')}
-          </MigrationPathLabel>
-        </MigrationPathRow>
-      </div>
-    )
-
-    // 显示确认模态框
-    window.modal.confirm({
-      title,
-      className,
-      width: 'min(600px, 90vw)',
-      style: { minHeight: '400px' },
-      content: (
-        <MigrationModalContent>
-          <PathsContent />
-          <CopyDataContent />
-          <MigrationNotice>
-            <p style={{ color: 'var(--color-warning)' }}>{t('settings.data.app_data.restart_notice')}</p>
-            <p style={{ color: 'var(--color-text-3)', marginTop: '8px' }}>
-              {t('settings.data.app_data.copy_time_notice')}
-            </p>
-          </MigrationNotice>
-        </MigrationModalContent>
-      ),
-      centered: true,
-      okButtonProps: {
-        danger: true
-      },
-      okText: t('common.confirm'),
-      cancelText: t('common.cancel'),
-      onOk: async () => {
-        try {
-          if (shouldCopyData) {
-            if (await window.api.isNotEmptyDir(newPath)) {
-              doubleConfirmModalBeforeCopyData(newPath)
-              return
-            }
-
-            window.toast.info({
-              title: t('settings.data.app_data.restart_notice'),
-              timeout: 3000
-            })
-            setTimeoutTimer(
-              'showMigrationConfirmModal_1',
-              () => {
-                window.api.relaunchApp({
-                  args: ['--new-data-path=' + newPath]
-                })
-              },
-              500
-            )
-            return
-          }
-          // 如果不复制数据，直接设置新的应用数据路径
-          await window.api.setAppDataPath(newPath)
-          window.toast.success(t('settings.data.app_data.path_changed_without_copy'))
-
-          // 更新应用数据路径
-          setAppInfo(await window.api.getAppInfo())
-
-          // 通知用户并重启应用
-          setTimeoutTimer(
-            'showMigrationConfirmModal_2',
-            () => {
-              window.toast.success(t('settings.data.app_data.select_success'))
-              window.api.setStopQuitApp(false, '')
-              window.api.relaunchApp()
-            },
-            500
-          )
-        } catch (error) {
-          window.api.setStopQuitApp(false, '')
-          window.toast.error({
-            title: t('settings.data.app_data.path_change_failed') + ': ' + error,
-            timeout: 5000
-          })
-        }
-      }
-    })
-  }
-
-  useEffect(() => {
-    const handleDataMigration = async () => {
-      const newDataPath = await window.api.getDataPathFromArgs()
-      if (!newDataPath) return
-
-      const originalPath = (await window.api.getAppInfo())?.appDataPath
-      if (!originalPath) return
-
-      const title = (
-        <div style={{ fontSize: '18px', fontWeight: 'bold' }}>{t('settings.data.app_data.migration_title')}</div>
-      )
-      const className = 'migration-modal'
-
-      // 显示进度模态框
-      const showProgressModal = (title: React.ReactNode, className: string, PathsContent: React.FC) => {
-        let currentProgress = 0
-        let progressInterval: NodeJS.Timeout | null = null
-
-        // 创建进度更新模态框
-        const loadingModal = window.modal.info({
-          title,
-          className,
-          width: 'min(600px, 90vw)',
-          style: { minHeight: '400px' },
-          icon: <LoadingOutlined style={{ fontSize: 18 }} />,
-          content: (
-            <MigrationModalContent>
-              <PathsContent />
-              <MigrationNotice>
-                <p>{t('settings.data.app_data.copying')}</p>
-                <div style={{ marginTop: '12px' }}>
-                  <Progress percent={currentProgress} status="active" strokeWidth={8} />
-                </div>
-                <p style={{ color: 'var(--color-warning)', marginTop: '12px', fontSize: '13px' }}>
-                  {t('settings.data.app_data.copying_warning')}
-                </p>
-              </MigrationNotice>
-            </MigrationModalContent>
-          ),
-          centered: true,
-          closable: false,
-          maskClosable: false,
-          okButtonProps: { style: { display: 'none' } }
-        })
-
-        // 更新进度的函数
-        const updateProgress = (progress: number, status: 'active' | 'success' = 'active') => {
-          loadingModal.update({
-            title,
-            content: (
-              <MigrationModalContent>
-                <PathsContent />
-                <MigrationNotice>
-                  <p>{t('settings.data.app_data.copying')}</p>
-                  <div style={{ marginTop: '12px' }}>
-                    <Progress percent={Math.round(progress)} status={status} strokeWidth={8} />
-                  </div>
-                  <p style={{ color: 'var(--color-warning)', marginTop: '12px', fontSize: '13px' }}>
-                    {t('settings.data.app_data.copying_warning')}
-                  </p>
-                </MigrationNotice>
-              </MigrationModalContent>
-            )
-          })
-        }
-
-        // 开始模拟进度更新
-        progressInterval = setInterval(() => {
-          if (currentProgress < 95) {
-            currentProgress += Math.random() * 5 + 1
-            if (currentProgress > 95) currentProgress = 95
-            updateProgress(currentProgress)
-          }
-        }, 500)
-
-        return { loadingModal, progressInterval, updateProgress }
-      }
-
-      // 开始迁移数据
-      const startMigration = async (
-        originalPath: string,
-        newPath: string,
-        progressInterval: NodeJS.Timeout | null,
-        updateProgress: (progress: number, status?: 'active' | 'success') => void,
-        loadingModal: { destroy: () => void }
-      ): Promise<void> => {
-        // flush app data
-        await window.api.flushAppData()
-
-        // wait 2 seconds to flush app data
-        await new Promise((resolve) => setTimeoutTimer('startMigration_1', resolve, 2000))
-
-        // 开始复制过程
-        const copyResult = await window.api.copy(
-          originalPath,
-          newPath,
-          occupiedDirs.map((dir) => originalPath + '/' + dir)
-        )
-
-        // 停止进度更新
-        if (progressInterval) {
-          clearInterval(progressInterval)
-        }
-
-        // 显示100%完成
-        updateProgress(100, 'success')
-
-        if (!copyResult.success) {
-          // 延迟关闭加载模态框
-          await new Promise<void>((resolve) => {
-            setTimeoutTimer(
-              'startMigration_2',
-              () => {
-                loadingModal.destroy()
-                window.toast.error({
-                  title: t('settings.data.app_data.copy_failed') + ': ' + copyResult.error,
-                  timeout: 5000
-                })
-                resolve()
-              },
-              500
-            )
-          })
-
-          throw new Error(copyResult.error || 'Unknown error during copy')
-        }
-
-        // 在复制成功后设置新的AppDataPath
-        await window.api.setAppDataPath(newPath)
-
-        // 短暂延迟以显示100%完成
-        await new Promise((resolve) => setTimeoutTimer('startMigration_3', resolve, 500))
-
-        // 关闭加载模态框
-        loadingModal.destroy()
-
-        window.toast.success({
-          title: t('settings.data.app_data.copy_success'),
-          timeout: 2000
-        })
-      }
-
-      // Create PathsContent component for this specific migration
-      const PathsContent = () => (
-        <div>
-          <MigrationPathRow>
-            <MigrationPathLabel>{t('settings.data.app_data.original_path')}:</MigrationPathLabel>
-            <MigrationPathValue>{originalPath}</MigrationPathValue>
-          </MigrationPathRow>
-          <MigrationPathRow style={{ marginTop: '16px' }}>
-            <MigrationPathLabel>{t('settings.data.app_data.new_path')}:</MigrationPathLabel>
-            <MigrationPathValue>{newDataPath}</MigrationPathValue>
-          </MigrationPathRow>
-        </div>
-      )
-
-      const { loadingModal, progressInterval, updateProgress } = showProgressModal(title, className, PathsContent)
-      try {
-        window.api.setStopQuitApp(true, t('settings.data.app_data.stop_quit_app_reason'))
-        await startMigration(originalPath, newDataPath, progressInterval, updateProgress, loadingModal)
-
-        // 更新应用数据路径
-        setAppInfo(await window.api.getAppInfo())
-
-        // 通知用户并重启应用
-        setTimeoutTimer(
-          'handleDataMigration',
-          () => {
-            window.toast.success(t('settings.data.app_data.select_success'))
-            window.api.setStopQuitApp(false, '')
-            window.api.relaunchApp({
-              args: ['--user-data-dir=' + newDataPath]
-            })
-          },
-          1000
-        )
-      } catch (error) {
-        window.api.setStopQuitApp(false, '')
-        window.toast.error({
-          title: t('settings.data.app_data.copy_failed') + ': ' + error,
-          timeout: 5000
-        })
-      } finally {
-        if (progressInterval) {
-          clearInterval(progressInterval)
-        }
-        loadingModal.destroy()
-      }
-    }
-
-    handleDataMigration()
-    // dont add others to deps
-    // eslint-disable-next-line react-hooks/exhaustive-deps
-  }, [])
-
-  const onSkipBackupFilesChange = (value: boolean) => {
-    setSkipBackupFile(value)
-    dispatch(_setSkipBackupFile(value))
-  }
-
   return (
     <Container>
       <MenuList>
@@ -593,104 +100,7 @@ const DataSettings: FC = () => {
         )}
       </MenuList>
       <SettingContainer theme={theme} style={{ display: 'flex', flex: 1, height: '100%' }}>
-        {menu === 'data' && (
-          <>
-            <SettingGroup theme={theme}>
-              <SettingTitle>{t('settings.data.title')}</SettingTitle>
-              <SettingDivider />
-              <SettingRow>
-                <SettingRowTitle>{t('settings.general.backup.title')}</SettingRowTitle>
-                <HStack gap="5px" justifyContent="space-between">
-                  <Button onClick={BackupPopup.show} icon={<SaveIcon size={14} />}>
-                    {t('settings.general.backup.button')}
-                  </Button>
-                  <Button onClick={RestorePopup.show} icon={<FolderOpen size={14} />}>
-                    {t('settings.general.restore.button')}
-                  </Button>
-                </HStack>
-              </SettingRow>
-              <SettingDivider />
-              <SettingRow>
-                <SettingRowTitle>{t('settings.data.backup.skip_file_data_title')}</SettingRowTitle>
-                <Switch checked={skipBackupFile} onChange={onSkipBackupFilesChange} />
-              </SettingRow>
-              <SettingRow>
-                <SettingHelpText>{t('settings.data.backup.skip_file_data_help')}</SettingHelpText>
-              </SettingRow>
-              <SettingDivider />
-              <SettingRow>
-                <SettingRowTitle>{t('settings.data.export_to_phone.title')}</SettingRowTitle>
-                <HStack gap="5px" justifyContent="space-between">
-                  <Button onClick={LanTransferPopup.show} icon={<WifiOutlined size={14} />}>
-                    {t('settings.data.export_to_phone.lan.title')}
-                  </Button>
-                </HStack>
-              </SettingRow>
-            </SettingGroup>
-            <SettingGroup theme={theme}>
-              <SettingTitle>{t('settings.data.data.title')}</SettingTitle>
-              <SettingDivider />
-              <SettingRow>
-                <SettingRowTitle>{t('settings.data.app_data.label')}</SettingRowTitle>
-                <PathRow>
-                  <PathText
-                    style={{ color: 'var(--color-text-3)' }}
-                    onClick={() => handleOpenPath(appInfo?.appDataPath)}>
-                    {appInfo?.appDataPath}
-                  </PathText>
-                  <Tooltip title={t('settings.data.app_data.select')}>
-                    <FolderOutput onClick={handleSelectAppDataPath} style={{ cursor: 'pointer' }} size={16} />
-                  </Tooltip>
-                  <HStack gap="5px" style={{ marginLeft: '8px' }}>
-                    <Button onClick={() => handleOpenPath(appInfo?.appDataPath)}>
-                      {t('settings.data.app_data.open')}
-                    </Button>
-                  </HStack>
-                </PathRow>
-              </SettingRow>
-              <SettingDivider />
-              <SettingRow>
-                <SettingRowTitle>{t('settings.data.app_logs.label')}</SettingRowTitle>
-                <PathRow>
-                  <PathText style={{ color: 'var(--color-text-3)' }} onClick={() => handleOpenPath(appInfo?.logsPath)}>
-                    {appInfo?.logsPath}
-                  </PathText>
-                  <HStack gap="5px" style={{ marginLeft: '8px' }}>
-                    <Button onClick={() => handleOpenPath(appInfo?.logsPath)}>
-                      {t('settings.data.app_logs.button')}
-                    </Button>
-                  </HStack>
-                </PathRow>
-              </SettingRow>
-              <SettingDivider />
-              <SettingRow>
-                <SettingRowTitle>{t('settings.data.app_knowledge.label')}</SettingRowTitle>
-                <HStack alignItems="center" gap="5px">
-                  <Button onClick={handleRemoveAllFiles}>{t('settings.data.app_knowledge.button.delete')}</Button>
-                </HStack>
-              </SettingRow>
-              <SettingDivider />
-              <SettingRow>
-                <SettingRowTitle>
-                  {t('settings.data.clear_cache.title')}
-                  {cacheSize && <CacheText>({cacheSize}MB)</CacheText>}
-                </SettingRowTitle>
-                <HStack gap="5px">
-                  <Button onClick={handleClearCache}>{t('settings.data.clear_cache.button')}</Button>
-                </HStack>
-              </SettingRow>
-              <SettingDivider />
-              <SettingRow>
-                <SettingRowTitle>{t('settings.general.reset.title')}</SettingRowTitle>
-                <HStack gap="5px">
-                  <Button onClick={reset} danger>
-                    {t('settings.general.reset.title')}
-                  </Button>
-                </HStack>
-              </SettingRow>
-            </SettingGroup>
-          </>
-        )}
+        {menu === 'data' && <BasicDataSettings />}
         {menu === 'webdav' && <WebDavSettings />}
         {menu === 'nutstore' && <NutstoreSettings />}
         {menu === 's3' && <S3Settings />}
@@ -730,69 +140,4 @@ const MenuList = styled.div`
   }
 `
 
-const CacheText = styled(Typography.Text)`
-  color: var(--color-text-3);
-  font-size: 12px;
-  margin-left: 5px;
-  line-height: 16px;
-  display: inline-block;
-  vertical-align: middle;
-  text-align: left;
-`
-
-const PathText = styled(Typography.Text)`
-  flex: 1;
-  min-width: 0;
-  overflow: hidden;
-  text-overflow: ellipsis;
-  white-space: nowrap;
-  display: inline-block;
-  vertical-align: middle;
-  text-align: right;
-  margin-left: 5px;
-  cursor: pointer;
-`
-
-const PathRow = styled(HStack)`
-  min-width: 0;
-  flex: 1;
-  width: 0;
-  align-items: center;
-  gap: 5px;
-`
-
-// Add styled components for migration modal
-const MigrationModalContent = styled.div`
-  padding: 20px 0 10px;
-  display: flex;
-  flex-direction: column;
-`
-
-const MigrationNotice = styled.div`
-  margin-top: 24px;
-  font-size: 14px;
-`
-
-const MigrationPathRow = styled.div`
-  display: flex;
-  flex-direction: column;
-  gap: 5px;
-`
-
-const MigrationPathLabel = styled.div`
-  font-weight: 600;
-  font-size: 15px;
-  color: var(--color-text-1);
-`
-
-const MigrationPathValue = styled.div`
-  font-size: 14px;
-  color: var(--color-text-2);
-  background-color: var(--color-background-soft);
-  padding: 8px 12px;
-  border-radius: 4px;
-  word-break: break-all;
-  border: 1px solid var(--color-border);
-`
-
 export default DataSettings
diff --git a/src/renderer/src/services/BackupService.ts b/src/renderer/src/services/BackupService.ts
--- a/src/renderer/src/services/BackupService.ts
+++ b/src/renderer/src/services/BackupService.ts
@@ -64,32 +64,65 @@ async function deleteWebdavFileWithRetry(fileName: string, webdavConfig: WebDavC
 
 export async function backup(skipBackupFile: boolean) {
   const filename = `cherry-studio.${dayjs().format('YYYYMMDDHHmm')}.zip`
-  const fileContnet = await getBackupData()
   const selectFolder = await window.api.file.selectFolder()
   if (selectFolder) {
-    await window.api.backup.backup(filename, fileContnet, selectFolder, skipBackupFile)
+    // Use direct backup method - copy IndexedDB/LocalStorage directories directly
+    await window.api.backup.backup(filename, selectFolder, skipBackupFile)
     window.toast.success(i18n.t('message.backup.success'))
   }
 }
 
+export async function backupToLanTransfer() {
+  // Let user select save location first
+  const savePath = await window.api.file.selectFolder()
+
+  if (!savePath) {
+    return
+  }
+
+  // Create backup directly in the selected location
+  const backupData = await getBackupData()
+  await window.api.backup.createLanTransferBackup(backupData, savePath)
+
+  window.toast.success(i18n.t('settings.data.export_to_phone.file.export_success'))
+}
+
 export async function restore() {
   const notificationService = NotificationService.getInstance()
   const file = await window.api.file.open({ filters: [{ name: '备份文件', extensions: ['bak', 'zip'] }] })
 
   if (file) {
     try {
-      let data: Record<string, any> = {}
-
       // zip backup file
       if (file?.fileName.endsWith('.zip')) {
         const restoreData = await window.api.backup.restore(file.filePath)
-        data = JSON.parse(restoreData)
+
+        // Direct backup format returns void (app needs to relaunch)
+        // Legacy format returns JSON string that needs to be processed
+        if (restoreData !== undefined && restoreData !== null) {
+          const data = JSON.parse(restoreData)
+          await handleData(data)
+        } else {
+          // Direct backup was restored, app will relaunch
+          notificationService.send({
+            id: uuid(),
+            type: 'success',
+            title: i18n.t('common.success'),
+            message: i18n.t('message.restore.success'),
+            silent: false,
+            timestamp: Date.now(),
+            source: 'backup',
+            channel: 'system'
+          })
+          // App will relaunch automatically
+          return
+        }
       } else {
-        data = JSON.parse(await window.api.zip.decompress(file.content))
+        // Legacy .bak format
+        const data = JSON.parse(await window.api.zip.decompress(file.content))
+        await handleData(data)
       }
 
-      await handleData(data)
-
       notificationService.send({
         id: uuid(),
         type: 'success',
@@ -102,7 +135,11 @@ export async function restore() {
       })
     } catch (error) {
       logger.error('restore: Error restoring backup file:', error as Error)
-      window.toast.error(i18n.t('error.backup.file_format'))
+      window.modal.error({
+        title: i18n.t('error.backup.file_format'),
+        content: (error as Error).message,
+        centered: true
+      })
     }
   }
 }
@@ -182,11 +219,10 @@ export async function backupToWebdav({
   const timestamp = dayjs().format('YYYYMMDDHHmmss')
   const backupFileName = customFileName || `cherry-studio.${timestamp}.${hostname}.${deviceType}.zip`
   const finalFileName = backupFileName.endsWith('.zip') ? backupFileName : `${backupFileName}.zip`
-  const backupData = await getBackupData()
 
-  // 上传文件
+  // 上传文件 - Use direct backup method (copy IndexedDB/LocalStorage directories)
   try {
-    const success = await window.api.backup.backupToWebdav(backupData, {
+    const success = await window.api.backup.backupToWebdav({
       webdavHost,
       webdavUser,
       webdavPass,
@@ -311,8 +347,16 @@ export async function restoreFromWebdav(fileName?: string) {
       title: i18n.t('message.restore.failed'),
       content: error.message
     })
+    return
+  }
+
+  // Direct backup format (version 6+) returns undefined - app needs to relaunch
+  if (!data) {
+    logger.info('[WebDAVBackup] Direct backup restored, app will restart')
+    return
   }
 
+  // Legacy backup format (version <= 5) returns JSON string
   try {
     await handleData(JSON.parse(data))
   } catch (error) {
@@ -356,10 +400,10 @@ export async function backupToS3({
   const timestamp = dayjs().format('YYYYMMDDHHmmss')
   const backupFileName = customFileName || `cherry-studio.${timestamp}.${hostname}.${deviceType}.zip`
   const finalFileName = backupFileName.endsWith('.zip') ? backupFileName : `${backupFileName}.zip`
-  const backupData = await getBackupData()
 
   try {
-    const success = await window.api.backup.backupToS3(backupData, {
+    // Use direct backup method (copy IndexedDB/LocalStorage directories)
+    const success = await window.api.backup.backupToS3({
       ...s3Config,
       fileName: finalFileName
     })
@@ -469,6 +513,14 @@ export async function restoreFromS3(fileName?: string) {
       ...s3Config,
       fileName
     })
+
+    // Direct backup format (version 6+) returns undefined - app needs to relaunch
+    if (!restoreData) {
+      logger.info('[S3Backup] Direct backup restored, app will restart')
+      return
+    }
+
+    // Legacy backup format (version <= 5) returns JSON string
     const data = JSON.parse(restoreData)
     await handleData(data)
   }
@@ -964,10 +1016,10 @@ export async function backupToLocal({
   const timestamp = dayjs().format('YYYYMMDDHHmmss')
   const backupFileName = customFileName || `cherry-studio.${timestamp}.${hostname}.${deviceType}.zip`
   const finalFileName = backupFileName.endsWith('.zip') ? backupFileName : `${backupFileName}.zip`
-  const backupData = await getBackupData()
 
   try {
-    const result = await window.api.backup.backupToLocalDir(backupData, finalFileName, {
+    // Use direct backup method (copy IndexedDB/LocalStorage directories)
+    const result = await window.api.backup.backupToLocalDir(finalFileName, {
       localBackupDir,
       skipBackupFile: localBackupSkipBackupFile
     })
@@ -1078,6 +1130,14 @@ export async function restoreFromLocal(fileName: string) {
     const { localBackupDir: localBackupDirSetting } = store.getState().settings
     const localBackupDir = await window.api.resolvePath(localBackupDirSetting)
     const restoreData = await window.api.backup.restoreFromLocalBackup(fileName, localBackupDir)
+
+    // Direct backup format (version 6+) returns undefined - app needs to relaunch
+    if (!restoreData) {
+      logger.info('[LocalBackup] Direct backup restored, app will restart')
+      return true
+    }
+
+    // Legacy backup format (version <= 5) returns JSON string
     const data = JSON.parse(restoreData)
     await handleData(data)
 
diff --git a/src/renderer/src/services/NutstoreService.ts b/src/renderer/src/services/NutstoreService.ts
--- a/src/renderer/src/services/NutstoreService.ts
+++ b/src/renderer/src/services/NutstoreService.ts
@@ -7,7 +7,7 @@ import { NUTSTORE_HOST } from '@shared/config/nutstore'
 import dayjs from 'dayjs'
 import { type CreateDirectoryOptions } from 'webdav'
 
-import { getBackupData, handleData } from './BackupService'
+import { handleData } from './BackupService'
 
 const logger = loggerService.withContext('NutstoreService')
 
@@ -143,15 +143,14 @@ export async function backupToNutstore({
 
   store.dispatch(setNutstoreSyncState({ syncing: true, lastSyncError: null }))
 
-  const backupData = await getBackupData()
   const skipBackupFile = store.getState().nutstore.nutstoreSkipBackupFile
   const maxBackups = store.getState().nutstore.nutstoreMaxBackups
 
   try {
     // 先清理旧备份
     await cleanupOldBackups(config, maxBackups)
 
-    const isSuccess = await window.api.backup.backupToWebdav(backupData, {
+    const isSuccess = await window.api.backup.backupToWebdav({
       ...config,
       fileName: finalFileName,
       skipBackupFile: skipBackupFile
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
