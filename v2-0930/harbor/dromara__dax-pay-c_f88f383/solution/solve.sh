#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/daxpay-payment/daxpay-payment-admin/src/main/java/cn/daxpay/open/payment/admin/controller/develop/DevelopAuthAdminController.java b/daxpay-payment/daxpay-payment-admin/src/main/java/cn/daxpay/open/payment/admin/controller/develop/DevelopAuthAdminController.java
--- a/daxpay-payment/daxpay-payment-admin/src/main/java/cn/daxpay/open/payment/admin/controller/develop/DevelopAuthAdminController.java
+++ b/daxpay-payment/daxpay-payment-admin/src/main/java/cn/daxpay/open/payment/admin/controller/develop/DevelopAuthAdminController.java
@@ -1,6 +1,6 @@
 package cn.daxpay.open.payment.admin.controller.develop;
 
-import cn.daxpay.open.payment.auth.DevelopAuthService;
+import cn.daxpay.open.payment.auth.develop.DevelopAuthService;
 import cn.daxpay.open.payment.unipay.param.assist.GenerateAuthUrlParam;
 import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
 import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
@@ -66,7 +66,7 @@ public Result<AuthUrlResult> generateDouyinAuthUrl() {
     @PostMapping("/generate-channel-auth-url")
     public Result<AuthUrlResult> generateChannelAuthUrl(@RequestBody GenerateAuthUrlParam param) {
         // 不加 @Valid: GenerateAuthUrlParam 继承 PaymentCommonParam.reqTime(@NotNull), 但认证不走签名/防重放, 无需 reqTime;
-        // channel/mchNo 由 ChannelProductAuthService 业务层兜底校验, 与 unipay ChannelAuthController 同类接口保持一致
+        // channel/mchNo 由 ProductAuthService 业务层兜底校验, 与 unipay ChannelAuthController 同类接口保持一致
         return Res.ok(developAuthService.generateChannelAuthUrl(param));
     }
 
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/ChannelAuthService.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/ChannelAuthService.java
deleted file mode 100644
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/ChannelAuthService.java
+++ /dev/null
@@ -1,112 +0,0 @@
-package cn.daxpay.open.payment.auth;
-
-import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
-import cn.daxpay.open.payment.unipay.param.assist.GenerateAuthUrlParam;
-import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
-import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
-import cn.daxpay.open.platform.core.code.DaxPayErrorCode;
-import cn.daxpay.open.platform.core.enums.unipay.ChannelAuthStatusEnum;
-import cn.daxpay.open.platform.core.enums.unipay.ChannelAuthTypeEnum;
-import cn.daxpay.open.platform.core.exception.BizInfoException;
-import cn.hutool.core.util.StrUtil;
-import lombok.RequiredArgsConstructor;
-import lombok.extern.slf4j.Slf4j;
-import org.springframework.stereotype.Service;
-
-import java.util.Objects;
-
-/// # 通道认证服务
-///
-/// 统一对外的「生成授权链接 / 授权码换用户标识」入口, 按会话来源与 authType 分流到
-/// [PlatformAuthService](平台级配置) 或 [ChannelProductAuthService](商户级产品策略)。
-/// Controller / 调试入口只做协议适配, 不在 Web 层写业务分支。
-///
-/// ## 分发优先级(auth)
-/// 1. session.source = platform_alipay / platform_mp / platform_douyin → 平台服务对应方法
-/// 2. authType=alipay 且无 session → 平台支付宝(小程序等直连兜底)
-/// 3. 其余 → 支付产品策略
-@Slf4j
-@Service
-@RequiredArgsConstructor
-public class ChannelAuthService {
-
-    private final AuthSessionStore authSessionStore;
-    private final PlatformAuthService platformAuthService;
-    private final ChannelProductAuthService channelProductAuthService;
-
-    /// 生成授权链接: 支付宝走平台级 OAuth, 其余按支付产品走通道策略
-    public AuthUrlResult generateAuthUrl(GenerateAuthUrlParam param) {
-        if (isAlipayAuth(param.getAuthType())) {
-            // 透传 returnPath, 供码牌等业务页授权完成后回跳
-            return platformAuthService.generateAlipayAuthUrl(param.getReturnPath());
-        }
-        return channelProductAuthService.generateAuthUrl(param);
-    }
-
-    /// 通过 AuthCode 换取认证结果, 成功后销毁会话(一次使用)
-    public AuthResult auth(AuthCodeParam param) {
-        AuthSession session = authSessionStore.loadSession(param.getAuthToken());
-        // 会话已失效(且非支付宝直连兜底场景): 提示重新生成, 避免下游抛"不支持的能力: null"
-        // 支付宝平台级 OAuth 不依赖 session 字段, 由 doAuth 内的兜底分支处理, 保持原行为
-        if (session == null && !isAlipayAuth(param.getAuthType())) {
-            // 授权链接已失效, 请重新生成
-            throw new BizInfoException(DaxPayErrorCode.OPERATION_FAIL,
-                    "pay.error.assist.authSessionExpired");
-        }
-        AuthResult result;
-        try {
-            result = doAuth(param, session);
-        } catch (RuntimeException e) {
-            // 认证失败: 写回 FAIL 状态供前端轮询及时退出(避免死等 TTL), 再抛原异常由调用方处理
-            authSessionStore.writeResultByQueryCode(param.getQueryCode(), session,
-                    new AuthResult().setStatus(ChannelAuthStatusEnum.FAIL.getCode()));
-            throw e;
-        }
-        // 平台级 auth 方法未回填 returnPath 时, 从会话补齐
-        if (session != null && StrUtil.isNotBlank(session.getReturnPath())
-                && StrUtil.isBlank(result.getReturnPath())) {
-            result.setReturnPath(session.getReturnPath());
-        }
-        // 成功后失效 authToken, 避免 TTL 内重复消费会话上下文
-        authSessionStore.deleteSession(param.getAuthToken());
-        return result;
-    }
-
-    /// 按会话来源把授权码回调分到平台或支付产品处理
-    private AuthResult doAuth(AuthCodeParam param, AuthSession session) {
-        if (isPlatformAlipay(session)) {
-            return platformAuthService.authAlipay(param, session);
-        }
-        if (isPlatformMp(session)) {
-            return platformAuthService.authWechatMp(param, session);
-        }
-        if (isPlatformDouyin(session)) {
-            return platformAuthService.authDouyin(param, session);
-        }
-        // 无会话且 authType=alipay: 小程序等直连场景兜底
-        if (isAlipayAuth(param.getAuthType()) && session == null) {
-            return platformAuthService.authAlipay(param, null);
-        }
-        return channelProductAuthService.auth(param, session);
-    }
-
-    /// 是否支付宝认证类型(平台级支付宝走 OAuth)
-    private boolean isAlipayAuth(String authType) {
-        return Objects.equals(authType, ChannelAuthTypeEnum.ALIPAY.getCode());
-    }
-
-    /// 是否支付宝平台级配置来源
-    private boolean isPlatformAlipay(AuthSession session) {
-        return session != null && AuthSession.SOURCE_PLATFORM_ALIPAY.equals(session.getSource());
-    }
-
-    /// 是否微信系统公众号配置来源(平台级)
-    private boolean isPlatformMp(AuthSession session) {
-        return session != null && AuthSession.SOURCE_PLATFORM_MP.equals(session.getSource());
-    }
-
-    /// 是否抖音 H5 应用配置来源(平台级)
-    private boolean isPlatformDouyin(AuthSession session) {
-        return session != null && AuthSession.SOURCE_PLATFORM_DOUYIN.equals(session.getSource());
-    }
-}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/PlatformAuthService.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/PlatformAuthService.java
deleted file mode 100644
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/PlatformAuthService.java
+++ /dev/null
@@ -1,253 +0,0 @@
-package cn.daxpay.open.payment.auth;
-
-import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
-import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
-import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
-import cn.daxpay.open.platform.capability.alipay.auth.config.AlipayAuthConfig;
-import cn.daxpay.open.platform.capability.alipay.auth.result.AlipayAuthResult;
-import cn.daxpay.open.platform.capability.alipay.auth.service.AlipayAuthCapability;
-import cn.daxpay.open.platform.capability.douyin.auth.result.DouyinAuthResult;
-import cn.daxpay.open.platform.capability.douyin.auth.service.DouyinH5AuthService;
-import cn.daxpay.open.platform.capability.wechat.auth.result.WechatAuthResult;
-import cn.daxpay.open.platform.capability.wechat.auth.result.WechatAuthUrlResult;
-import cn.daxpay.open.platform.capability.wechat.auth.service.WechatMpAuthService;
-import cn.daxpay.open.platform.core.code.CommonErrorCode;
-import cn.daxpay.open.platform.core.enums.unipay.ChannelAuthStatusEnum;
-import cn.daxpay.open.platform.core.exception.BizInfoException;
-import cn.daxpay.open.platform.system.entity.config.platform.auth.PlatformAlipayAuthConfig;
-import cn.daxpay.open.platform.system.entity.config.platform.auth.PlatformDouyinH5AuthConfig;
-import cn.daxpay.open.platform.system.entity.config.platform.auth.PlatformWechatMpAuthConfig;
-import cn.daxpay.open.platform.system.service.config.auth.PlatformAlipayAuthConfigService;
-import cn.daxpay.open.platform.system.service.config.auth.PlatformDouyinH5AuthConfigService;
-import cn.daxpay.open.platform.system.service.config.auth.PlatformWechatMpAuthConfigService;
-import cn.daxpay.open.platform.system.service.config.infra.PlatformUrlConfigService;
-import cn.hutool.core.util.IdUtil;
-import cn.hutool.core.util.RandomUtil;
-import cn.hutool.core.util.StrUtil;
-import lombok.RequiredArgsConstructor;
-import lombok.extern.slf4j.Slf4j;
-import org.springframework.stereotype.Service;
-
-/// # 平台级认证服务
-///
-/// 承载不依赖商户上下文、由平台级配置驱动的认证场景:
-/// - **支付宝**: 平台级支付宝配置, OAuth 重定向, 调试/支付共用; URL 拼装见 [#buildAlipayAuthUrl],
-///   通道策略 [cn.daxpay.open.payment.strategy.auth.AlipayAuthStrategy] 亦委托本服务, 避免双轨实现
-/// - **微信系统公众号配置**: 平台级微信公众号配置([PlatformWechatMpAuthConfig]), OAuth 重定向, **仅调试场景**
-///   (网关聚合/收银台/码牌支付走通道应用策略, 不再消费本配置)
-/// - **抖音 H5 应用**: 平台级抖音 H5 配置([PlatformDouyinH5AuthConfig]), silent_auth 静默授权, **仅调试场景**
-///
-/// 与按支付产品路由策略的 [ChannelProductAuthService] 解耦: 本服务不读取商户级通道配置,
-/// 只消费平台级配置并调用 capability(alipay/wechat/douyin) 用授权码换 token/openId; 会话与结果缓存委托 [AuthSessionStore]。
-/// 对外分发入口见 [ChannelAuthService]。
-///
-/// 三通道统一模式: 固定 redirect_uri + OAuth state 透传 authToken, 回调后从 state 恢复会话。
-@Slf4j
-@Service
-@RequiredArgsConstructor
-public class PlatformAuthService {
-
-    /// 支付宝授权范围: auth_base(静默授权, 仅取 userId, 不弹确认页)
-    private static final String ALIPAY_SCOPE = "auth_base";
-
-    private final AuthSessionStore authSessionStore;
-    private final PlatformAlipayAuthConfigService platformAlipayAuthConfigService;
-    private final PlatformWechatMpAuthConfigService platformWechatMpAuthConfigService;
-    private final PlatformDouyinH5AuthConfigService platformDouyinH5AuthConfigService;
-    private final PlatformUrlConfigService platformUrlConfigService;
-    private final AlipayAuthCapability alipayAuthCapability;
-    private final WechatMpAuthService wechatMpAuthService;
-    private final DouyinH5AuthService douyinH5AuthService;
-
-    /// 生成支付宝授权链接(平台级, 无商户上下文)
-    ///
-    /// 读取平台级 [PlatformAlipayAuthConfig], 调用 capability-alipay 生成支付宝 OAuth 授权链接,
-    /// 回调指向固定的 `/auth/alipay`。会话标识 authToken 通过 OAuth state 参数透传, 回调后从 state 恢复会话。
-    /// session 标记 `source=platform_alipay`, 认证分发层据此走平台级支付宝授权回调分支([#authAlipay])。
-    public AuthUrlResult generateAlipayAuthUrl() {
-        return generateAlipayAuthUrl(null);
-    }
-
-    /// 生成支付宝授权链接, 可携带授权完成后前端回跳路径
-    ///
-    /// @param returnPath 授权完成后前端业务回跳路径(如 `/cashier/{orderNo}/alipay`), 可空
-    public AuthUrlResult generateAlipayAuthUrl(String returnPath) {
-        String authToken = IdUtil.fastSimpleUUID();
-        String queryCode = RandomUtil.randomString(10);
-        AuthSession session = new AuthSession()
-                .setSource(AuthSession.SOURCE_PLATFORM_ALIPAY)
-                .setQueryCode(queryCode)
-                .setReturnPath(returnPath);
-        authSessionStore.saveSession(authToken, session);
-        String authUrl = buildAlipayAuthUrl(authToken);
-        authSessionStore.saveWaitingResult(queryCode);
-        return new AuthUrlResult().setAuthUrl(authUrl).setQueryCode(queryCode);
-    }
-
-    /// 仅拼装支付宝 OAuth 授权 URL(不创建会话)
-    ///
-    /// 供 [cn.daxpay.open.payment.strategy.auth.AlipayAuthStrategy] 复用: 通道侧已由
-    /// [ChannelProductAuthService] 创建 session/queryCode, 策略层只负责拼 URL, 避免与平台路径双份实现。
-    public String buildAlipayAuthUrl(String authToken) {
-        AlipayAuthConfig config = platformAlipayAuthConfigService.toCapabilityConfig();
-        if (!alipayAuthCapability.isConfigured(config)) {
-            // 支付宝: 平台级支付宝配置不完整, 请先在「三方平台管理」中配置
-            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.social.alipayNotConfigured");
-        }
-        // redirect_uri 为固定路径(见 [AuthRedirectUri]), authToken 通过 OAuth state 透传
-        String redirectUri = AuthRedirectUri.ALIPAY.buildRedirectUri(platformUrlConfigService);
-        return alipayAuthCapability.generateAuthUrl(config, redirectUri, ALIPAY_SCOPE, authToken, false);
-    }
-
-    /// 生成微信系统公众号配置授权链接(平台级, 无商户上下文, 仅调试)
-    ///
-    /// 读取平台级 [PlatformWechatMpAuthConfig], 调用 capability-wechat 生成微信公众号 OAuth 授权链接,
-    /// 回调指向固定的 `/auth/wechat`。会话标识 authToken 通过 OAuth state 参数透传, 回调后从 state 恢复会话。
-    /// session 标记 `source=platform_mp`, 认证分发层据此走平台级微信授权回调分支([#authWechatMp])。
-    public AuthUrlResult generateWechatMpAuthUrl() {
-        return generateWechatMpAuthUrl(null);
-    }
-
-    /// 生成微信公众号授权链接, 可携带授权完成后前端回跳路径
-    ///
-    /// @param returnPath 授权完成后前端业务回跳路径(如 `/cashier/{orderNo}/wechat`), 可空
-    public AuthUrlResult generateWechatMpAuthUrl(String returnPath) {
-        PlatformWechatMpAuthConfig config = platformWechatMpAuthConfigService.getWechatMpAuthConfig();
-        if (!isWechatMpConfigured(config)) {
-            // 微信: 平台级微信公众号配置不完整, 请先在「平台配置」中配置
-            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.social.wechatMpNotConfigured");
-        }
-        String authToken = IdUtil.fastSimpleUUID();
-        String queryCode = RandomUtil.randomString(10);
-        AuthSession session = new AuthSession()
-                .setSource(AuthSession.SOURCE_PLATFORM_MP)
-                .setQueryCode(queryCode)
-                .setReturnPath(returnPath);
-        authSessionStore.saveSession(authToken, session);
-        // redirect_uri 为固定路径(见 [AuthRedirectUri]), authToken 通过 OAuth state 透传
-        String redirectUri = AuthRedirectUri.WECHAT.buildRedirectUri(platformUrlConfigService);
-        WechatAuthUrlResult result = wechatMpAuthService.generateAuthUrl(redirectUri, config.getAppId(), config.getAppSecret(), authToken);
-        authSessionStore.saveWaitingResult(queryCode);
-        return new AuthUrlResult().setAuthUrl(result.getAuthUrl()).setQueryCode(queryCode);
-    }
-
-    /// 生成抖音 H5 静默授权链接(平台级, 无商户上下文, 仅调试)
-    ///
-    /// 读取平台级 [PlatformDouyinH5AuthConfig], 调用 capability-douyin [DouyinH5AuthService] 构造 silent_auth 链接,
-    /// 回调指向固定的 `/auth/douyin`(抖音要求 redirect_uri 与平台配置完全一致, 不支持 path 段或 query 参数)。
-    /// 会话标识 authToken 通过 state 参数透传, 回调后从 state 恢复会话。
-    /// session 标记 `source=platform_douyin`, 认证分发层据此走平台级抖音授权回调分支([#authDouyin])。
-    public AuthUrlResult generateDouyinAuthUrl() {
-        return generateDouyinAuthUrl(null);
-    }
-
-    /// 生成抖音 H5 静默授权链接, 可携带授权完成后前端回跳路径
-    ///
-    /// @param returnPath 授权完成后前端业务回跳路径, 可空
-    public AuthUrlResult generateDouyinAuthUrl(String returnPath) {
-        PlatformDouyinH5AuthConfig config = platformDouyinH5AuthConfigService.getDouyinH5AuthConfig();
-        if (!isDouyinH5Configured(config)) {
-            // 抖音: 平台级抖音 H5 应用配置不完整, 请先在「三方平台管理」中配置
-            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.social.douyinH5NotConfigured");
-        }
-        String authToken = IdUtil.fastSimpleUUID();
-        String queryCode = RandomUtil.randomString(10);
-        AuthSession session = new AuthSession()
-                .setSource(AuthSession.SOURCE_PLATFORM_DOUYIN)
-                .setQueryCode(queryCode)
-                .setReturnPath(returnPath);
-        authSessionStore.saveSession(authToken, session);
-        // redirect_uri 为固定路径(见 [AuthRedirectUri], 抖音要求与平台配置完全一致), authToken 通过 state 透传
-        String redirectUri = AuthRedirectUri.DOUYIN.buildRedirectUri(platformUrlConfigService);
-        String authUrl = douyinH5AuthService.buildSilentAuthUrl(config.getClientKey(), redirectUri, authToken);
-        authSessionStore.saveWaitingResult(queryCode);
-        return new AuthUrlResult().setAuthUrl(authUrl).setQueryCode(queryCode);
-    }
-
-    /// 支付宝 authCode 换 userId/openId(平台级配置)
-    ///
-    /// 统一映射: 支付链路按 openId 取值, 同时回填 userId; 结果落库供 queryCode 轮询。
-    /// queryCode 优先从 param 取, 其次从 session 恢复(OAuth 回调场景)。
-    public AuthResult authAlipay(AuthCodeParam param, AuthSession session) {
-        AlipayAuthConfig config = platformAlipayAuthConfigService.toCapabilityConfig();
-        if (!alipayAuthCapability.isConfigured(config)) {
-            // 支付宝: 平台级支付宝配置不完整, 请先在「三方平台管理」中配置
-            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.social.alipayNotConfigured");
-        }
-        AlipayAuthResult alipayResult = alipayAuthCapability.getUserId(config, param.getAuthCode());
-        String userId = StrUtil.blankToDefault(alipayResult.getUserId(), alipayResult.getOpenId());
-        if (StrUtil.isBlank(userId)) {
-            // 支付宝: 获取用户标识失败
-            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.alipay.authFailed", "userId is blank");
-        }
-        AuthResult authResult = new AuthResult()
-                .setOpenId(userId)
-                .setUserId(userId)
-                .setAccessToken(alipayResult.getAccessToken())
-                .setStatus(ChannelAuthStatusEnum.SUCCESS.getCode());
-        // 回填业务回跳路径, 供前端跳回收银台/聚合等页面
-        fillReturnPath(authResult, session);
-        authSessionStore.writeResultByQueryCode(param.getQueryCode(), session, authResult);
-        return authResult;
-    }
-
-    /// 微信系统公众号平台级用授权码换 openId(读 [PlatformWechatMpAuthConfig])
-    public AuthResult authWechatMp(AuthCodeParam param, AuthSession session) {
-        PlatformWechatMpAuthConfig config = platformWechatMpAuthConfigService.getWechatMpAuthConfig();
-        if (!isWechatMpConfigured(config)) {
-            // 微信: 平台级微信公众号配置不完整, 请先在「平台配置」中配置
-            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.social.wechatMpNotConfigured");
-        }
-        WechatAuthResult data = wechatMpAuthService.getTokenAndOpenId(param.getAuthCode(), config.getAppId(), config.getAppSecret());
-        if (StrUtil.isBlank(data.getOpenId())) {
-            // 微信: 获取openId失败
-            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.channel.wechat.authFailed", "openId is blank");
-        }
-        AuthResult authResult = new AuthResult()
-                .setOpenId(data.getOpenId())
-                .setAccessToken(data.getAccessToken())
-                .setStatus(ChannelAuthStatusEnum.SUCCESS.getCode());
-        fillReturnPath(authResult, session);
-        authSessionStore.writeResultByQueryCode(param.getQueryCode(), session, authResult);
-        return authResult;
-    }
-
-    /// 微信系统公众号配置是否完整(appId/appSecret 均非空)
-    private boolean isWechatMpConfigured(PlatformWechatMpAuthConfig config) {
-        return StrUtil.isNotBlank(config.getAppId()) && StrUtil.isNotBlank(config.getAppSecret());
-    }
-
-    /// 抖音 H5 应用平台级用授权码换 openId(读 [PlatformDouyinH5AuthConfig])
-    public AuthResult authDouyin(AuthCodeParam param, AuthSession session) {
-        PlatformDouyinH5AuthConfig config = platformDouyinH5AuthConfigService.getDouyinH5AuthConfig();
-        if (!isDouyinH5Configured(config)) {
-            // 抖音: 平台级抖音 H5 应用配置不完整, 请先在「三方平台管理」中配置
-            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.social.douyinH5NotConfigured");
-        }
-        DouyinAuthResult data = douyinH5AuthService.getOpenIdByCode(
-                config.getClientKey(), config.getClientSecret(), param.getAuthCode());
-        if (StrUtil.isBlank(data.getOpenId())) {
-            // 抖音: 获取用户标识失败
-            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.douyin.authFailed", "openId is blank");
-        }
-        AuthResult authResult = new AuthResult()
-                .setOpenId(data.getOpenId())
-                .setAccessToken(data.getAccessToken())
-                .setStatus(ChannelAuthStatusEnum.SUCCESS.getCode());
-        fillReturnPath(authResult, session);
-        authSessionStore.writeResultByQueryCode(param.getQueryCode(), session, authResult);
-        return authResult;
-    }
-
-    /// 抖音 H5 应用配置是否完整(clientKey/clientSecret 均非空)
-    private boolean isDouyinH5Configured(PlatformDouyinH5AuthConfig config) {
-        return StrUtil.isNotBlank(config.getClientKey()) && StrUtil.isNotBlank(config.getClientSecret());
-    }
-
-    /// 将会话中的 returnPath 回填到认证结果
-    private void fillReturnPath(AuthResult authResult, AuthSession session) {
-        if (session != null && StrUtil.isNotBlank(session.getReturnPath())) {
-            authResult.setReturnPath(session.getReturnPath());
-        }
-    }
-}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthRedirectUri.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthRedirectUri.java
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthRedirectUri.java
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthRedirectUri.java
@@ -1,4 +1,4 @@
-package cn.daxpay.open.payment.auth;
+package cn.daxpay.open.payment.auth.core;
 
 import cn.daxpay.open.platform.core.code.DaxPayErrorCode;
 import cn.daxpay.open.platform.core.exception.BizInfoException;
@@ -9,10 +9,7 @@
 
 /// # 通道认证 OAuth 回调路径
 ///
-/// 收敛三通道(支付宝 / 微信公众号 / 抖音 H5)的固定回调路径常量与 redirect_uri 拼装逻辑,
-/// 消除原 [PlatformAuthService] 三个常量(ALIPAY_AUTH_PATH/WECHAT_AUTH_PATH/DOUYIN_AUTH_PATH)与
-/// 各通道策略(WechatIsvAuthStrategy / WechatDirectAuthStrategy / DouyinDirectAuthStrategy)中
-/// 重复的 gatewayBase 空检查 + `removeSuffix("/") + 字面量路径` 拼装。
+/// 收敛三通道(支付宝 / 微信公众号 / 抖音 H5)的固定回调路径常量与 redirect_uri 拼装逻辑。
 ///
 /// ## 约定
 /// - 回调路径固定(不含动态段),会话标识 authToken 通过 OAuth state 参数透传,回调后从 state 恢复
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthScene.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthScene.java
new file mode 100644
--- /dev/null
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthScene.java
@@ -0,0 +1,34 @@
+package cn.daxpay.open.payment.auth.core;
+
+import lombok.Getter;
+import lombok.RequiredArgsConstructor;
+import cn.daxpay.open.payment.auth.merchant.ChannelAuthService;
+
+/// # 认证场景
+///
+/// 按业务目的将通道认证入口分为三类, 与签名方式、返回方式无关:
+///
+/// - **PAYMENT**: 支付认证 — 为完成 JSAPI/小程序支付获取用户标识(openId/userId)。
+///   包括签名面 API(ChannelAuthController) 和网关 H5(GatewayClientController) 两个入口,
+///   区别仅在安全验证方式, Service 层不区分。
+///
+/// - **PLATFORM**: 平台自用认证 — 系统自身功能需要的认证(调试验证配置 / 社交登录 / 消息通知等)。
+///   使用平台级配置, 不依赖商户通道。其中调试走 ChannelAuthService; 社交登录和消息通知有独立流程。
+///
+/// - **OPEN**: 对外开放认证 — 对接方通过 DaxPay 获取用户标识(重定向模式, 非 JSON 返回)。
+///   类似海科融通 getOpenid 接口: 对接方上送 redirect_url, 系统完成 OAuth 后重定向回去带 openid。
+@Getter
+@RequiredArgsConstructor
+public enum AuthScene {
+
+    /// 支付认证: 为完成支付获取用户标识
+    PAYMENT("payment"),
+
+    /// 平台自用认证: 系统功能自用(调试/通知/社交登录)
+    PLATFORM("platform"),
+
+    /// 对外开放认证: 对接方获取用户标识(重定向接口)
+    OPEN("open");
+
+    private final String code;
+}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthSession.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthSession.java
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthSession.java
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthSession.java
@@ -1,36 +1,40 @@
-package cn.daxpay.open.payment.auth;
+package cn.daxpay.open.payment.auth.core;
 
 import lombok.Data;
 import lombok.experimental.Accessors;
+import cn.daxpay.open.payment.auth.platform.AlipayAuthProvider;
+import cn.daxpay.open.payment.auth.platform.WechatMpAuthProvider;
+import cn.daxpay.open.payment.auth.platform.DouyinH5AuthProvider;
+import cn.daxpay.open.payment.auth.merchant.ProductAuthService;
 
 /// # 认证会话上下文
 ///
 /// H5授权重定向场景下, 生成授权链接时将认证所需上下文序列化保存到Redis(以 authToken 为key),
 /// 授权回调后凭 authToken 恢复, 供认证策略定位通道应用并完成 code 换 openId/userId。
-/// 与 [ChannelProductAuthService] 的 queryCode 机制(付款码/道通场景)解耦, 独立 key 前缀管理。
+/// 与 [ProductAuthService] 的 queryCode 机制(付款码/道通场景)解耦, 独立 key 前缀管理。
 @Data
 @Accessors(chain = true)
 public class AuthSession {
 
     /// 认证来源: 平台级支付宝配置(系统支付宝配置调试场景)
     ///
     /// 该标记表示本次认证使用平台级 `PlatformAlipayAuthConfig` 用授权码换 openId,
-    /// 而非商户级支付产品策略。由 [PlatformAuthService] 在 generateAlipayAuthUrl 时写入,
-    /// 认证分发层据此走平台级支付宝授权回调分支([PlatformAuthService#authAlipay])。
+    /// 而非商户级支付产品策略。由 [AlipayAuthProvider] 在 generateAuthUrl 时写入,
+    /// 认证分发层据此走平台级支付宝授权回调分支([AlipayAuthProvider#auth])。
     public static final String SOURCE_PLATFORM_ALIPAY = "platform_alipay";
 
     /// 认证来源: 平台级微信公众号配置(系统公众号配置调试场景)
     ///
     /// 该标记表示本次认证使用平台级 `PlatformWechatMpAuthConfig`(appId/appSecret) 用授权码换 openId,
-    /// 而非商户级支付产品策略。由 [PlatformAuthService] 在 generateWechatMpAuthUrl 时写入,
-    /// 认证分发层据此走平台级微信授权回调分支([PlatformAuthService#authWechatMp])。
+    /// 而非商户级支付产品策略。由 [WechatMpAuthProvider] 在 generateAuthUrl 时写入,
+    /// 认证分发层据此走平台级微信授权回调分支([WechatMpAuthProvider#auth])。
     public static final String SOURCE_PLATFORM_MP = "platform_mp";
 
     /// 认证来源: 平台级抖音 H5 应用配置(抖音支付调试场景)
     ///
     /// 该标记表示本次认证使用平台级 `PlatformDouyinH5AuthConfig`(clientKey/clientSecret) 用授权码换 openId,
-    /// 通过抖音开放平台 silent_auth 静默授权获取 openId。由 [PlatformAuthService] 在
-    /// generateDouyinAuthUrl 时写入, 认证分发层据此走平台级抖音授权回调分支([PlatformAuthService#authDouyin])。
+    /// 通过抖音开放平台 silent_auth 静默授权获取 openId。由 [DouyinH5AuthProvider] 在
+    /// generateAuthUrl 时写入, 认证分发层据此走平台级抖音授权回调分支([DouyinH5AuthProvider#auth])。
     public static final String SOURCE_PLATFORM_DOUYIN = "platform_douyin";
 
     /// 认证来源
@@ -59,6 +63,16 @@ public class AuthSession {
     /// 来源回跳路径(授权完成后前端回跳的目标路径)
     private String returnPath;
 
+    /// 认证场景
+    ///
+    /// 标识本次认证的业务目的:
+    /// - [AuthScene#PAYMENT]: 支付认证(签名API + 网关H5)
+    /// - [AuthScene#PLATFORM]: 平台自用认证(调试/通知/社交登录)
+    /// - [AuthScene#OPEN]: 对外开放认证(重定向获取用户标识)
+    ///
+    /// 由各场景入口在创建会话时写入, 供回调处理时区分结果返回方式(JSON vs 302重定向)。
+    private String scene;
+
     /// 查询码(调试轮询用)
     ///
     /// OAuth 重定向场景下, 回调 URL 仅含 authToken(第三方不透传 queryCode),
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthSessionStore.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthSessionStore.java
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthSessionStore.java
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/core/AuthSessionStore.java
@@ -1,4 +1,4 @@
-package cn.daxpay.open.payment.auth;
+package cn.daxpay.open.payment.auth.core;
 
 import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
 import cn.daxpay.open.platform.common.json.util.JacksonUtil;
@@ -11,12 +11,19 @@
 
 import java.time.Duration;
 import java.util.Objects;
+import cn.daxpay.open.payment.auth.platform.AlipayAuthProvider;
+import cn.daxpay.open.payment.auth.platform.WechatMpAuthProvider;
+import cn.daxpay.open.payment.auth.platform.DouyinH5AuthProvider;
+import cn.daxpay.open.payment.auth.merchant.ChannelAuthService;
+import cn.daxpay.open.payment.auth.merchant.ProductAuthService;
+import cn.daxpay.open.payment.auth.develop.DevelopAuthService;
 
 /// # 认证会话与结果缓存
 ///
 /// 统一管理通道认证/平台级认证共用的会话上下文(authToken)与轮询结果(queryCode)的 Redis 读写,
-/// 与具体认证来源(通道商户策略 / 平台级配置)解耦, 供 [ChannelAuthService]、[ChannelProductAuthService]、
-/// [PlatformAuthService] 及各端调试入口(admin DevelopAuthAdminService / merchant MchDevelopAuthService)复用。
+/// 与具体认证来源(通道商户策略 / 平台级配置)解耦, 供 [ChannelAuthService]、[ProductAuthService]、
+/// 各 PlatformAuthProvider([AlipayAuthProvider]/[WechatMpAuthProvider]/[DouyinH5AuthProvider])
+/// 及调试入口([DevelopAuthService])复用。
 /// 授权成功后由 Facade 调用 [#deleteSession] 使 authToken 一次使用失效。
 @Slf4j
 @Service
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/DevelopAuthService.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/develop/DevelopAuthService.java
rename from daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/DevelopAuthService.java
rename to daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/develop/DevelopAuthService.java
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/DevelopAuthService.java
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/develop/DevelopAuthService.java
@@ -1,55 +1,58 @@
-package cn.daxpay.open.payment.auth;
+package cn.daxpay.open.payment.auth.develop;
 
 import cn.daxpay.open.payment.unipay.param.assist.GenerateAuthUrlParam;
 import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
 import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
 import lombok.RequiredArgsConstructor;
 import lombok.extern.slf4j.Slf4j;
 import org.springframework.stereotype.Service;
+import cn.daxpay.open.payment.auth.core.AuthSessionStore;
+import cn.daxpay.open.payment.auth.platform.AlipayAuthProvider;
+import cn.daxpay.open.payment.auth.platform.DouyinH5AuthProvider;
+import cn.daxpay.open.payment.auth.platform.WechatMpAuthProvider;
+import cn.daxpay.open.payment.auth.merchant.ProductAuthService;
 
 /// # 认证调试服务(运营端 / 商户端共用)
 ///
 /// 调试入口, 按认证来源分别委托:
-/// - **支付宝(平台级)**: 委托 [PlatformAuthService] 生成 OAuth 授权链接, 轮询 queryCode 取结果
-/// - **微信公众号配置(平台级)**: 委托 [PlatformAuthService], OAuth 重定向取 openId, 仅验证配置是否正确
-/// - **抖音H5(平台级)**: 委托 [PlatformAuthService], silent_auth 静默授权取 openId, 仅验证配置是否正确
-/// - **微信支付(直连/服务商)**: 委托 [ChannelProductAuthService] 按支付产品路由认证策略,
+/// - **支付宝(平台级)**: 委托 [AlipayAuthProvider] 生成 OAuth 授权链接, 轮询 queryCode 取结果
+/// - **微信公众号配置(平台级)**: 委托 [WechatMpAuthProvider], OAuth 重定向取 openId, 仅验证配置是否正确
+/// - **抖音H5(平台级)**: 委托 [DouyinH5AuthProvider], silent_auth 静默授权取 openId, 仅验证配置是否正确
+/// - **微信支付(直连/服务商)**: 委托 [ProductAuthService] 按支付产品路由认证策略,
 ///   依赖商户上下文(channelMchNo/产品/能力)
 /// - **支付宝小程序**: 暂未实现
 /// - **微信小程序(商户端/运营端)**: 暂未实现
 ///
 /// 已实现项共用 queryCode 轮询机制(由 [AuthSessionStore#queryAuthResult] 统一查询)。
-///
-/// ## 重构说明
-/// 原 `DevelopAuthAdminService` 与 `MchDevelopAuthService` 逐行相同, 已合并到 payment-core 本类,
-/// 运营端/商户端 Controller 直接注入, 消除冗余中间层。
 @Slf4j
 @Service
 @RequiredArgsConstructor
 public class DevelopAuthService {
 
-    private final PlatformAuthService platformAuthService;
-    private final ChannelProductAuthService channelProductAuthService;
+    private final AlipayAuthProvider alipayAuthProvider;
+    private final WechatMpAuthProvider wechatMpAuthProvider;
+    private final DouyinH5AuthProvider douyinH5AuthProvider;
+    private final ProductAuthService channelProductAuthService;
     private final AuthSessionStore authSessionStore;
 
     /// 生成支付宝授权链接(平台级 OAuth + queryCode 轮询)
     public AuthUrlResult generateAlipayAuthUrl() {
-        return platformAuthService.generateAlipayAuthUrl();
+        return alipayAuthProvider.generateAuthUrl(null);
     }
 
     /// 生成微信公众号配置授权链接(平台级, 仅调试)
     public AuthUrlResult generateWechatMpAuthUrl() {
-        return platformAuthService.generateWechatMpAuthUrl();
+        return wechatMpAuthProvider.generateAuthUrl(null);
     }
 
     /// 生成抖音 H5 授权链接(平台级, 仅调试)
     public AuthUrlResult generateDouyinAuthUrl() {
-        return platformAuthService.generateDouyinAuthUrl();
+        return douyinH5AuthProvider.generateAuthUrl(null);
     }
 
     /// 生成微信支付(直连/服务商)授权链接
     ///
-    /// 委托 [ChannelProductAuthService#generateAuthUrl], 按支付产品路由对应认证策略:
+    /// 委托 [ProductAuthService#generateAuthUrl], 按支付产品路由对应认证策略:
     /// 直连(WECHAT_PAY) → WechatDirectAuthStrategy; 服务商(WECHAT_ISV) → WechatIsvAuthStrategy。
     public AuthUrlResult generateChannelAuthUrl(GenerateAuthUrlParam param) {
         return channelProductAuthService.generateAuthUrl(param);
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/strategy/auth/AbsChannelAuthStrategy.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/AbsProductAuthStrategy.java
rename from daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/strategy/auth/AbsChannelAuthStrategy.java
rename to daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/AbsProductAuthStrategy.java
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/strategy/auth/AbsChannelAuthStrategy.java
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/AbsProductAuthStrategy.java
@@ -1,7 +1,6 @@
-package cn.daxpay.open.payment.strategy.auth;
+package cn.daxpay.open.payment.auth.merchant;
 
-import cn.daxpay.open.payment.auth.AuthSession;
-import cn.daxpay.open.payment.auth.ChannelProductAuthService;
+import cn.daxpay.open.payment.auth.core.AuthSession;
 import cn.daxpay.open.payment.strategy.PaymentStrategy;
 import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
 import cn.daxpay.open.payment.unipay.param.assist.GenerateAuthUrlParam;
@@ -13,11 +12,11 @@
 ///
 /// 负责获取支付所需的用户标识(微信 openId / 支付宝 userId)。按支付产品([cn.daxpay.open.platform.core.enums.pay.channel.ProductEnum])
 /// 注册, 与支付策略粒度一致。策略复用支付的商户配置体系定位通道应用(appId/appSecret)。
-public abstract class AbsChannelAuthStrategy implements PaymentStrategy {
+public abstract class AbsProductAuthStrategy implements PaymentStrategy {
 
     /// 获取授权链接
     ///
-    /// @param authToken 认证会话码, 由上层 [ChannelProductAuthService] 生成注入,
+    /// @param authToken 认证会话码, 由上层 [ProductAuthService] 生成注入,
     ///                  策略负责将其拼入回调地址; 授权回跳时凭此恢复上下文。
     public abstract AuthUrlResult generateAuthUrl(GenerateAuthUrlParam param, String authToken);
 
@@ -29,17 +28,17 @@ public abstract class AbsChannelAuthStrategy implements PaymentStrategy {
 
     /// 解析认证上下文: session 字段优先, param 兜底
     ///
-    /// 抽取各通道策略 doAuth 开头重复的「session 非空判断 + param 回退」逻辑, 返回
-    /// [AuthContext](channelMchNo / capability / channelAppId)。H5 OAuth 重定向场景从 session
-    /// 恢复(param 仅含 authToken); 小程序直连场景 session 为空, 从 param 取上下文。
-    protected AuthContext resolveContext(AuthCodeParam param, AuthSession session) {
+    /// H5 OAuth 重定向场景从 session 恢复(param 仅含 authToken);
+    /// 小程序直连场景 session 为空, 从 param 取上下文。
+    /// 返回 [ProductAuthContext](channelMchNo / capability / channelAppId)。
+    protected ProductAuthContext resolveContext(AuthCodeParam param, AuthSession session) {
         String channelMchNo = session != null && StrUtil.isNotBlank(session.getChannelMchNo())
                 ? session.getChannelMchNo() : param.getChannelMchNo();
         String capability = session != null && StrUtil.isNotBlank(session.getCapability())
                 ? session.getCapability() : param.getCapability();
         String channelAppId = session != null && StrUtil.isNotBlank(session.getChannelAppId())
                 ? session.getChannelAppId() : param.getChannelAppId();
-        return new AuthContext(channelMchNo, capability, channelAppId);
+        return new ProductAuthContext(channelMchNo, capability, channelAppId);
     }
 
 }
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/ChannelAuthService.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/ChannelAuthService.java
new file mode 100644
--- /dev/null
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/ChannelAuthService.java
@@ -0,0 +1,128 @@
+package cn.daxpay.open.payment.auth.merchant;
+
+import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
+import cn.daxpay.open.payment.unipay.param.assist.GenerateAuthUrlParam;
+import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
+import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
+import cn.daxpay.open.platform.core.code.DaxPayErrorCode;
+import cn.daxpay.open.platform.core.enums.unipay.ChannelAuthStatusEnum;
+import cn.daxpay.open.platform.core.enums.unipay.ChannelAuthTypeEnum;
+import cn.daxpay.open.platform.core.exception.BizInfoException;
+import cn.hutool.core.util.StrUtil;
+import lombok.extern.slf4j.Slf4j;
+import org.springframework.stereotype.Service;
+
+import java.util.List;
+import java.util.Map;
+import java.util.function.Function;
+import java.util.stream.Collectors;
+import cn.daxpay.open.payment.auth.core.AuthSession;
+import cn.daxpay.open.payment.auth.core.AuthSessionStore;
+import cn.daxpay.open.payment.auth.platform.PlatformAuthProvider;
+
+/// # 通道认证服务
+///
+/// 统一对外的「生成授权链接 / 授权码换用户标识」入口, 按会话来源([AuthSession#getSource])与
+/// authType 分流到平台级 [PlatformAuthProvider](按 source 注册)或商户级产品策略([ProductAuthService])。
+/// Controller / 调试入口只做协议适配, 不在 Web 层写业务分支。
+///
+/// ## 分发机制
+/// 平台级认证 Provider 按 [PlatformAuthProvider#sourceCode] 注册到 `providers` Map, 查找 O(1)。
+/// 新增平台级通道只需新增 [PlatformAuthProvider] 实现, 无需改本类。
+///
+/// ## 分发优先级(auth)
+/// 1. `session.source` 命中 `providers` → 平台级 Provider 对应方法
+/// 2. 无 session 且 `authType` 映射到平台级 source(支付宝小程序直连兜底)→ Provider
+/// 3. 其余 → 商户级产品策略
+///
+/// ## 分发优先级(generateAuthUrl)
+/// - `authType=alipay` → 平台级支付宝 Provider(无商户上下文)
+/// - 其余 → 商户级产品策略(微信/抖音需商户上下文定位应用)
+@Slf4j
+@Service
+public class ChannelAuthService {
+
+    private final AuthSessionStore authSessionStore;
+    private final ProductAuthService channelProductAuthService;
+    /// 平台级认证 Provider 按 [PlatformAuthProvider#sourceCode] 索引
+    private final Map<String, PlatformAuthProvider> providers;
+
+    public ChannelAuthService(AuthSessionStore authSessionStore,
+                              ProductAuthService channelProductAuthService,
+                              List<PlatformAuthProvider> providerList) {
+        this.authSessionStore = authSessionStore;
+        this.channelProductAuthService = channelProductAuthService;
+        // 按 sourceCode 索引, doAuth 据会话来源 O(1) 查找
+        this.providers = providerList.stream()
+                .collect(Collectors.toMap(PlatformAuthProvider::sourceCode, Function.identity()));
+    }
+
+    /// 生成授权链接: 支付宝走平台级 Provider, 其余按支付产品走通道策略
+    public AuthUrlResult generateAuthUrl(GenerateAuthUrlParam param) {
+        String source = mapAuthTypeToSource(param.getAuthType());
+        if (source != null) {
+            return providers.get(source).generateAuthUrl(param.getReturnPath());
+        }
+        return channelProductAuthService.generateAuthUrl(param);
+    }
+
+    /// 通过 AuthCode 换取认证结果, 成功后销毁会话(一次使用)
+    public AuthResult auth(AuthCodeParam param) {
+        AuthSession session = authSessionStore.loadSession(param.getAuthToken());
+        // 会话已失效(且非平台级认证的无 session 兜底场景): 提示重新生成, 避免下游抛"不支持的能力: null"
+        // 平台级 authType(如 alipay)不依赖 session 字段, 由 doAuth 内的兜底分支处理
+        if (session == null && mapAuthTypeToSource(param.getAuthType()) == null) {
+            // 授权链接已失效, 请重新生成
+            throw new BizInfoException(DaxPayErrorCode.OPERATION_FAIL,
+                    "pay.error.assist.authSessionExpired");
+        }
+        AuthResult result;
+        try {
+            result = doAuth(param, session);
+        } catch (RuntimeException e) {
+            // 认证失败: 写回 FAIL 状态供前端轮询及时退出(避免死等 TTL), 再抛原异常由调用方处理
+            authSessionStore.writeResultByQueryCode(param.getQueryCode(), session,
+                    new AuthResult().setStatus(ChannelAuthStatusEnum.FAIL.getCode()));
+            throw e;
+        }
+        // 平台级 auth 方法未回填 returnPath 时, 从会话补齐
+        if (session != null && StrUtil.isNotBlank(session.getReturnPath())
+                && StrUtil.isBlank(result.getReturnPath())) {
+            result.setReturnPath(session.getReturnPath());
+        }
+        // 成功后失效 authToken, 避免 TTL 内重复消费会话上下文
+        authSessionStore.deleteSession(param.getAuthToken());
+        return result;
+    }
+
+    /// 按会话来源把授权码回调分到平台 Provider 或支付产品处理
+    private AuthResult doAuth(AuthCodeParam param, AuthSession session) {
+        // session.source 标记的平台级认证, 按 source 查 Provider
+        if (session != null && StrUtil.isNotBlank(session.getSource())) {
+            PlatformAuthProvider provider = providers.get(session.getSource());
+            if (provider != null) {
+                return provider.auth(param, session);
+            }
+        }
+        // 无 session 且 authType 对应平台级 Provider(如支付宝小程序直连): 兜底走 Provider
+        if (session == null) {
+            String source = mapAuthTypeToSource(param.getAuthType());
+            if (source != null) {
+                return providers.get(source).auth(param, null);
+            }
+        }
+        // 其余: 商户级产品策略
+        return channelProductAuthService.auth(param, session);
+    }
+
+    /// authType → 平台级 Provider source 映射
+    ///
+    /// 仅支付宝走平台级 generate/auth(不依赖商户上下文); 微信/抖音 generate/auth 需商户上下文定位应用,
+    /// 走 [ProductAuthService] 按支付产品路由。
+    private static String mapAuthTypeToSource(String authType) {
+        if (ChannelAuthTypeEnum.ALIPAY.getCode().equals(authType)) {
+            return AuthSession.SOURCE_PLATFORM_ALIPAY;
+        }
+        return null;
+    }
+}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/ProductAuthContext.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/ProductAuthContext.java
new file mode 100644
--- /dev/null
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/ProductAuthContext.java
@@ -0,0 +1,13 @@
+package cn.daxpay.open.payment.auth.merchant;
+
+/// # 认证上下文(通道应用定位信息)
+///
+/// 由 [AbsProductAuthStrategy#resolveContext] 从「session 优先、param 兜底」解析得出,
+/// 供各通道策略在 [AbsProductAuthStrategy#doAuth] 中定位通道应用(appId/appSecret)。
+///
+/// ## 字段含义
+/// - `channelMchNo`: 通道商户号(定位特约商户主数据 / 反查 mchNo)
+/// - `capability`: 支付能力编码(公众号 / 小程序, 决定应用维度与 openId 类型)
+/// - `channelAppId`: 显式指定的应用 AppId(可选, 优先级高于配置自动解析)
+public record ProductAuthContext(String channelMchNo, String capability, String channelAppId) {
+}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/ChannelProductAuthService.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/ProductAuthService.java
rename from daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/ChannelProductAuthService.java
rename to daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/ProductAuthService.java
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/ChannelProductAuthService.java
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/merchant/ProductAuthService.java
@@ -1,15 +1,18 @@
-package cn.daxpay.open.payment.auth;
+package cn.daxpay.open.payment.auth.merchant;
 
+import cn.daxpay.open.payment.auth.core.AuthScene;
+import cn.daxpay.open.payment.auth.core.AuthSession;
+import cn.daxpay.open.payment.auth.core.AuthSessionStore;
 import cn.daxpay.open.payment.merchant.dao.channel.ChannelMerchantManager;
 import cn.daxpay.open.payment.merchant.entity.channel.ChannelMerchant;
 import cn.daxpay.open.payment.common.context.MerchantContextLoader;
 import cn.daxpay.open.payment.strategy.PaymentStrategyFactory;
-import cn.daxpay.open.payment.strategy.auth.AbsChannelAuthStrategy;
 import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
 import cn.daxpay.open.payment.unipay.param.assist.GenerateAuthUrlParam;
 import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
 import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
 import cn.daxpay.open.platform.core.code.CommonErrorCode;
+import cn.daxpay.open.platform.core.enums.pay.channel.ProductEnum;
 import cn.daxpay.open.platform.core.enums.unipay.ChannelAuthStatusEnum;
 import cn.daxpay.open.platform.core.exception.BizInfoException;
 import cn.hutool.core.util.IdUtil;
@@ -18,34 +21,36 @@
 import lombok.RequiredArgsConstructor;
 import lombok.extern.slf4j.Slf4j;
 import org.springframework.stereotype.Service;
+import cn.daxpay.open.payment.auth.platform.PlatformAuthProvider;
 
 /// # 支付产品认证服务(商户级)
 ///
-/// 负责按支付产品路由认证策略(继承 [AbsChannelAuthStrategy]), 依赖商户上下文定位通道应用,
+/// 负责按支付产品路由认证策略(继承 [AbsProductAuthStrategy]), 依赖商户上下文定位通道应用,
 /// 获取支付所需的用户标识(微信 openId / 支付宝 userId)。H5 授权重定向场景生成 authToken 保存会话。
 ///
 /// **职责边界**: 本服务仅处理商户级通道认证; 平台级认证(平台支付宝配置 / 系统公众号配置)
-/// 由 [PlatformAuthService] 承担, 会话与结果缓存由 [AuthSessionStore] 统一管理。
+/// 由各 [PlatformAuthProvider] 承担, 会话与结果缓存由 [AuthSessionStore] 统一管理。
 /// 平台级 vs 通道级 的来源分发由 [ChannelAuthService] 完成, 请勿在 Controller 再写分流。
 @Slf4j
 @Service
 @RequiredArgsConstructor
-public class ChannelProductAuthService {
+public class ProductAuthService {
 
     private final AuthSessionStore authSessionStore;
     private final MerchantContextLoader merchantContextLoader;
     private final ChannelMerchantManager channelMerchantManager;
 
     /// 获取通道授权链接
     ///
-    /// 生成 authToken 并委托产品策略([AbsChannelAuthStrategy])生成授权 URL, 会话随 authToken 保存,
+    /// 生成 authToken 并委托产品策略([AbsProductAuthStrategy])生成授权 URL, 会话随 authToken 保存,
     /// 授权回调后凭此恢复上下文。同时生成 queryCode 供调试轮询(微信等 OAuth 重定向通道回调 URL
     /// 不含 queryCode, 需随会话保存)。
     public AuthUrlResult generateAuthUrl(GenerateAuthUrlParam param) {
         initMchContext(param.getAppId(), param.getMchNo(), null);
         // 支付产品: 显式传入优先, 否则从通道商户号反查(调试工具/直接指定通道商户场景)
         String product = resolveProduct(param);
-        var strategy = PaymentStrategyFactory.createByProduct(product, AbsChannelAuthStrategy.class);
+        assertNotAlipayProduct(product);
+        var strategy = PaymentStrategyFactory.createByProduct(product, AbsProductAuthStrategy.class);
         // 生成认证会话码并保存上下文, 授权回调后凭此恢复
         String authToken = IdUtil.fastSimpleUUID();
         // 生成 queryCode 供调试轮询(微信等 OAuth 重定向通道回调 URL 不含 queryCode, 需随会话保存)
@@ -56,11 +61,13 @@ public AuthUrlResult generateAuthUrl(GenerateAuthUrlParam param) {
                 .setCapability(param.getCapability())
                 .setChannelAppId(param.getChannelAppId())
                 .setReturnPath(param.getReturnPath())
-                .setQueryCode(queryCode);
+                .setQueryCode(queryCode)
+                .setScene(AuthScene.PAYMENT.getCode());
         authSessionStore.saveSession(authToken, session);
         AuthUrlResult authUrlResult = strategy.generateAuthUrl(param, authToken);
         // 回填 queryCode 并写入 WAITING 状态供前端轮询
         authUrlResult.setQueryCode(queryCode);
+        authUrlResult.setAuthToken(authToken);
         authSessionStore.saveWaitingResult(queryCode);
         return authUrlResult;
     }
@@ -74,7 +81,8 @@ public AuthResult auth(AuthCodeParam param, AuthSession session) {
         // product 优先从会话恢复, 其次取参数(小程序直连场景)
         String product = (session != null && StrUtil.isNotBlank(session.getProduct()))
                 ? session.getProduct() : param.getProduct();
-        var strategy = PaymentStrategyFactory.createByProduct(product, AbsChannelAuthStrategy.class);
+        assertNotAlipayProduct(product);
+        var strategy = PaymentStrategyFactory.createByProduct(product, AbsProductAuthStrategy.class);
         AuthResult authResult = strategy.doAuth(param, session);
         authResult.setStatus(ChannelAuthStatusEnum.SUCCESS.getCode());
         // 会话恢复场景: 回填来源回跳路径, 供前端跳回业务页面
@@ -121,4 +129,11 @@ private String resolveProduct(GenerateAuthUrlParam param) {
                 .orElseThrow(() -> new BizInfoException(CommonErrorCode.VALIDATE_PARAMETERS_ERROR,
                         "pay.error.assist.channelMchNotFound", param.getChannelMchNo()));
     }
+
+    /// 支付宝认证统一走平台级 PlatformAuthProvider, 不应进入产品策略; 触发即编程错误。
+    private void assertNotAlipayProduct(String product) {
+        if (ProductEnum.ALIPAY.getCode().equals(product) || ProductEnum.ALIPAY_ISV.getCode().equals(product)) {
+            throw new IllegalStateException("支付宝认证应走平台级 Provider, 不应进入产品策略: " + product);
+        }
+    }
 }
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/AlipayAuthProvider.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/AlipayAuthProvider.java
new file mode 100644
--- /dev/null
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/AlipayAuthProvider.java
@@ -0,0 +1,100 @@
+package cn.daxpay.open.payment.auth.platform;
+
+import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
+import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
+import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
+import cn.daxpay.open.platform.capability.alipay.auth.config.AlipayAuthConfig;
+import cn.daxpay.open.platform.capability.alipay.auth.result.AlipayAuthResult;
+import cn.daxpay.open.platform.capability.alipay.auth.service.AlipayAuthCapability;
+import cn.daxpay.open.platform.core.code.CommonErrorCode;
+import cn.daxpay.open.platform.core.enums.unipay.ChannelAuthStatusEnum;
+import cn.daxpay.open.platform.core.exception.BizInfoException;
+import cn.daxpay.open.platform.system.service.config.auth.PlatformAlipayAuthConfigService;
+import cn.daxpay.open.platform.system.service.config.infra.PlatformUrlConfigService;
+import cn.hutool.core.util.IdUtil;
+import cn.hutool.core.util.RandomUtil;
+import cn.hutool.core.util.StrUtil;
+import lombok.RequiredArgsConstructor;
+import lombok.extern.slf4j.Slf4j;
+import org.springframework.stereotype.Component;
+import cn.daxpay.open.payment.auth.core.AuthScene;
+import cn.daxpay.open.payment.auth.core.AuthSession;
+import cn.daxpay.open.payment.auth.core.AuthSessionStore;
+import cn.daxpay.open.payment.auth.core.AuthRedirectUri;
+import cn.daxpay.open.payment.auth.merchant.ChannelAuthService;
+
+/// # 支付宝平台级认证 Provider
+///
+/// 会话标记 `source=platform_alipay`, 认证分发层 [ChannelAuthService] 据 source 查找本 Provider。
+@Slf4j
+@Component
+@RequiredArgsConstructor
+public class AlipayAuthProvider implements PlatformAuthProvider {
+
+    /// 支付宝授权范围: auth_base(静默授权, 仅取 userId, 不弹确认页)
+    private static final String ALIPAY_SCOPE = "auth_base";
+
+    private final AuthSessionStore authSessionStore;
+    private final PlatformAlipayAuthConfigService platformAlipayAuthConfigService;
+    private final PlatformUrlConfigService platformUrlConfigService;
+    private final AlipayAuthCapability alipayAuthCapability;
+
+    @Override
+    public String sourceCode() {
+        return AuthSession.SOURCE_PLATFORM_ALIPAY;
+    }
+
+    /// 生成支付宝授权链接
+    ///
+    /// 配置校验前置, 再建 session/queryCode 落 Redis, 最后拼装授权 URL。
+    @Override
+    public AuthUrlResult generateAuthUrl(String returnPath) {
+        // 配置校验前置, 避免配置缺失时 session 残留至 TTL
+        AlipayAuthConfig config = loadConfigOrThrow();
+        String authToken = IdUtil.fastSimpleUUID();
+        String queryCode = RandomUtil.randomString(10);
+        AuthSession session = new AuthSession()
+                .setSource(AuthSession.SOURCE_PLATFORM_ALIPAY)
+                .setQueryCode(queryCode)
+                .setReturnPath(returnPath)
+                .setScene(AuthScene.PLATFORM.getCode());
+        authSessionStore.saveSession(authToken, session);
+        // redirect_uri 为固定路径(见 [AuthRedirectUri]), authToken 通过 OAuth state 透传
+        String redirectUri = AuthRedirectUri.ALIPAY.buildRedirectUri(platformUrlConfigService);
+        String authUrl = alipayAuthCapability.generateAuthUrl(config, redirectUri, ALIPAY_SCOPE, authToken, false);
+        authSessionStore.saveWaitingResult(queryCode);
+        return new AuthUrlResult().setAuthUrl(authUrl).setQueryCode(queryCode).setAuthToken(authToken);
+    }
+
+    /// 通过 authCode 换 userId/openId(平台级配置)
+    ///
+    /// 统一映射: 支付链路按 openId 取值, 同时回填 userId; 结果落库供 queryCode 轮询。
+    @Override
+    public AuthResult auth(AuthCodeParam param, AuthSession session) {
+        AlipayAuthConfig config = loadConfigOrThrow();
+        AlipayAuthResult alipayResult = alipayAuthCapability.getUserId(config, param.getAuthCode());
+        String userId = StrUtil.blankToDefault(alipayResult.getUserId(), alipayResult.getOpenId());
+        if (StrUtil.isBlank(userId)) {
+            // 支付宝: 获取用户标识失败
+            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.alipay.authFailed", "userId is blank");
+        }
+        AuthResult authResult = new AuthResult()
+                .setOpenId(userId)
+                .setUserId(userId)
+                .setAccessToken(alipayResult.getAccessToken())
+                .setStatus(ChannelAuthStatusEnum.SUCCESS.getCode());
+        fillReturnPath(authResult, session);
+        authSessionStore.writeResultByQueryCode(param.getQueryCode(), session, authResult);
+        return authResult;
+    }
+
+    /// 加载支付宝配置并校验完整性
+    private AlipayAuthConfig loadConfigOrThrow() {
+        AlipayAuthConfig config = platformAlipayAuthConfigService.toCapabilityConfig();
+        if (!alipayAuthCapability.isConfigured(config)) {
+            // 支付宝: 平台级支付宝配置不完整, 请先在「三方平台管理」中配置
+            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.social.alipayNotConfigured");
+        }
+        return config;
+    }
+}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/DouyinH5AuthProvider.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/DouyinH5AuthProvider.java
new file mode 100644
--- /dev/null
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/DouyinH5AuthProvider.java
@@ -0,0 +1,92 @@
+package cn.daxpay.open.payment.auth.platform;
+
+import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
+import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
+import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
+import cn.daxpay.open.platform.capability.douyin.auth.result.DouyinAuthResult;
+import cn.daxpay.open.platform.capability.douyin.auth.service.DouyinH5AuthService;
+import cn.daxpay.open.platform.core.code.CommonErrorCode;
+import cn.daxpay.open.platform.core.enums.unipay.ChannelAuthStatusEnum;
+import cn.daxpay.open.platform.core.exception.BizInfoException;
+import cn.daxpay.open.platform.system.entity.config.platform.auth.PlatformDouyinH5AuthConfig;
+import cn.daxpay.open.platform.system.service.config.auth.PlatformDouyinH5AuthConfigService;
+import cn.daxpay.open.platform.system.service.config.infra.PlatformUrlConfigService;
+import cn.hutool.core.util.IdUtil;
+import cn.hutool.core.util.RandomUtil;
+import cn.hutool.core.util.StrUtil;
+import lombok.RequiredArgsConstructor;
+import lombok.extern.slf4j.Slf4j;
+import org.springframework.stereotype.Component;
+import cn.daxpay.open.payment.auth.core.AuthScene;
+import cn.daxpay.open.payment.auth.core.AuthSession;
+import cn.daxpay.open.payment.auth.core.AuthSessionStore;
+import cn.daxpay.open.payment.auth.core.AuthRedirectUri;
+
+/// # 抖音 H5 平台级认证 Provider
+///
+/// 会话标记 `source=platform_douyin`, 仅调试场景使用。
+/// 抖音 silent_auth 要求 redirect_uri 与平台配置完全一致。
+@Slf4j
+@Component
+@RequiredArgsConstructor
+public class DouyinH5AuthProvider implements PlatformAuthProvider {
+
+    private final AuthSessionStore authSessionStore;
+    private final PlatformDouyinH5AuthConfigService platformDouyinH5AuthConfigService;
+    private final PlatformUrlConfigService platformUrlConfigService;
+    private final DouyinH5AuthService douyinH5AuthService;
+
+    @Override
+    public String sourceCode() {
+        return AuthSession.SOURCE_PLATFORM_DOUYIN;
+    }
+
+    @Override
+    public AuthUrlResult generateAuthUrl(String returnPath) {
+        PlatformDouyinH5AuthConfig config = loadConfigOrThrow();
+        String authToken = IdUtil.fastSimpleUUID();
+        String queryCode = RandomUtil.randomString(10);
+        AuthSession session = new AuthSession()
+                .setSource(AuthSession.SOURCE_PLATFORM_DOUYIN)
+                .setQueryCode(queryCode)
+                .setReturnPath(returnPath)
+                .setScene(AuthScene.PLATFORM.getCode());
+        authSessionStore.saveSession(authToken, session);
+        // redirect_uri 为固定路径(见 [AuthRedirectUri], 抖音要求与平台配置完全一致), authToken 通过 state 透传
+        String redirectUri = AuthRedirectUri.DOUYIN.buildRedirectUri(platformUrlConfigService);
+        String authUrl = douyinH5AuthService.buildSilentAuthUrl(config.getClientKey(), redirectUri, authToken);
+        authSessionStore.saveWaitingResult(queryCode);
+        return new AuthUrlResult().setAuthUrl(authUrl).setQueryCode(queryCode).setAuthToken(authToken);
+    }
+
+    @Override
+    public AuthResult auth(AuthCodeParam param, AuthSession session) {
+        PlatformDouyinH5AuthConfig config = loadConfigOrThrow();
+        DouyinAuthResult data = douyinH5AuthService.getOpenIdByCode(
+                config.getClientKey(), config.getClientSecret(), param.getAuthCode());
+        if (StrUtil.isBlank(data.getOpenId())) {
+            // 抖音: 获取用户标识失败
+            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.douyin.authFailed", "openId is blank");
+        }
+        AuthResult authResult = new AuthResult()
+                .setOpenId(data.getOpenId())
+                .setAccessToken(data.getAccessToken())
+                .setStatus(ChannelAuthStatusEnum.SUCCESS.getCode());
+        fillReturnPath(authResult, session);
+        authSessionStore.writeResultByQueryCode(param.getQueryCode(), session, authResult);
+        return authResult;
+    }
+
+    private PlatformDouyinH5AuthConfig loadConfigOrThrow() {
+        PlatformDouyinH5AuthConfig config = platformDouyinH5AuthConfigService.getDouyinH5AuthConfig();
+        if (!isConfigured(config)) {
+            // 抖音: 平台级抖音 H5 应用配置不完整, 请先在「三方平台管理」中配置
+            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.social.douyinH5NotConfigured");
+        }
+        return config;
+    }
+
+    private boolean isConfigured(PlatformDouyinH5AuthConfig config) {
+        return StrUtil.isNotBlank(config.getClientKey()) && StrUtil.isNotBlank(config.getClientSecret());
+    }
+}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/PlatformAuthProvider.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/PlatformAuthProvider.java
new file mode 100644
--- /dev/null
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/PlatformAuthProvider.java
@@ -0,0 +1,42 @@
+package cn.daxpay.open.payment.auth.platform;
+
+import cn.daxpay.open.payment.auth.merchant.ChannelAuthService;
+import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
+import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
+import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
+import cn.hutool.core.util.StrUtil;
+import cn.daxpay.open.payment.auth.core.AuthSession;
+import cn.daxpay.open.payment.auth.develop.DevelopAuthService;
+
+/// # 平台级认证 Provider(策略)
+///
+/// 抽象平台级认证场景(支付宝 / 微信公众号 / 抖音 H5), 按 [AuthSession#getSource] 注册,
+/// 供 [ChannelAuthService] 按会话来源 O(1) 查找。
+///
+/// ## 注册机制
+/// 每个实现以 `@Component` 注册, 通过 [#sourceCode] 声明对应的 [AuthSession] source 常量。
+/// 消费方([ChannelAuthService])注入 `List<PlatformAuthProvider>` 后按 sourceCode 建 Map 查找。
+public interface PlatformAuthProvider {
+
+    /// 认证来源标识
+    ///
+    /// 对应 [AuthSession#SOURCE_PLATFORM_ALIPAY] / [AuthSession#SOURCE_PLATFORM_MP] / [AuthSession#SOURCE_PLATFORM_DOUYIN]。
+    String sourceCode();
+
+    /// 生成授权链接(平台级, 无商户上下文)
+    ///
+    /// @param returnPath 授权完成后前端回跳路径, 可空
+    AuthUrlResult generateAuthUrl(String returnPath);
+
+    /// 通过 authCode 换认证结果
+    ///
+    /// @param session 认证会话上下文(含 queryCode/returnPath); 可能为 null
+    AuthResult auth(AuthCodeParam param, AuthSession session);
+
+    /// 将会话中的 returnPath 回填到认证结果(平台级 Provider 共用)
+    default void fillReturnPath(AuthResult authResult, AuthSession session) {
+        if (session != null && StrUtil.isNotBlank(session.getReturnPath())) {
+            authResult.setReturnPath(session.getReturnPath());
+        }
+    }
+}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/WechatMpAuthProvider.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/WechatMpAuthProvider.java
new file mode 100644
--- /dev/null
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/auth/platform/WechatMpAuthProvider.java
@@ -0,0 +1,99 @@
+package cn.daxpay.open.payment.auth.platform;
+
+import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
+import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
+import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
+import cn.daxpay.open.payment.wx.facade.WxAppFacade;
+import cn.daxpay.open.payment.wx.facade.WxAppView;
+import cn.daxpay.open.platform.capability.wechat.auth.result.WechatAuthResult;
+import cn.daxpay.open.platform.capability.wechat.auth.result.WechatAuthUrlResult;
+import cn.daxpay.open.platform.capability.wechat.auth.service.WechatMpAuthService;
+import cn.daxpay.open.platform.core.code.CommonErrorCode;
+import cn.daxpay.open.platform.core.enums.pay.channel.PayCapabilityEnum;
+import cn.daxpay.open.platform.core.enums.pay.channel.ProductEnum;
+import cn.daxpay.open.platform.core.enums.unipay.ChannelAuthStatusEnum;
+import cn.daxpay.open.platform.core.exception.BizInfoException;
+import cn.daxpay.open.platform.system.service.config.infra.PlatformUrlConfigService;
+import cn.hutool.core.util.IdUtil;
+import cn.hutool.core.util.RandomUtil;
+import cn.hutool.core.util.StrUtil;
+import lombok.RequiredArgsConstructor;
+import lombok.extern.slf4j.Slf4j;
+import org.springframework.stereotype.Component;
+import cn.daxpay.open.payment.auth.core.AuthScene;
+import cn.daxpay.open.payment.auth.core.AuthSession;
+import cn.daxpay.open.payment.auth.core.AuthSessionStore;
+import cn.daxpay.open.payment.auth.core.AuthRedirectUri;
+
+/// # 微信公众号平台级认证 Provider
+///
+/// 会话标记 `source=platform_mp`, 仅调试场景使用(网关聚合/收银台/码牌支付走通道应用策略)。
+///
+/// ## 配置来源
+/// 通过 [WxAppFacade] 从微信主数据(wx_platform_app)解析公众号(OFFICIAL_ACCOUNT)类型的平台应用。
+@Slf4j
+@Component
+@RequiredArgsConstructor
+public class WechatMpAuthProvider implements PlatformAuthProvider {
+
+    private final AuthSessionStore authSessionStore;
+    private final WxAppFacade wxAppFacade;
+    private final PlatformUrlConfigService platformUrlConfigService;
+    private final WechatMpAuthService wechatMpAuthService;
+
+    @Override
+    public String sourceCode() {
+        return AuthSession.SOURCE_PLATFORM_MP;
+    }
+
+    @Override
+    public AuthUrlResult generateAuthUrl(String returnPath) {
+        WxAppView app = loadPlatformAppOrThrow();
+        String authToken = IdUtil.fastSimpleUUID();
+        String queryCode = RandomUtil.randomString(10);
+        AuthSession session = new AuthSession()
+                .setSource(AuthSession.SOURCE_PLATFORM_MP)
+                .setQueryCode(queryCode)
+                .setReturnPath(returnPath)
+                .setScene(AuthScene.PLATFORM.getCode());
+        authSessionStore.saveSession(authToken, session);
+        // redirect_uri 为固定路径(见 [AuthRedirectUri]), authToken 通过 OAuth state 透传
+        String redirectUri = AuthRedirectUri.WECHAT.buildRedirectUri(platformUrlConfigService);
+        WechatAuthUrlResult result = wechatMpAuthService.generateAuthUrl(redirectUri, app.wxAppId(), app.appSecret(), authToken);
+        authSessionStore.saveWaitingResult(queryCode);
+        return new AuthUrlResult().setAuthUrl(result.getAuthUrl()).setQueryCode(queryCode).setAuthToken(authToken);
+    }
+
+    @Override
+    public AuthResult auth(AuthCodeParam param, AuthSession session) {
+        WxAppView app = loadPlatformAppOrThrow();
+        WechatAuthResult data = wechatMpAuthService.getTokenAndOpenId(param.getAuthCode(), app.wxAppId(), app.appSecret());
+        if (StrUtil.isBlank(data.getOpenId())) {
+            // 微信: 获取openId失败
+            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR, "error.channel.wechat.authFailed", "openId is blank");
+        }
+        AuthResult authResult = new AuthResult()
+                .setOpenId(data.getOpenId())
+                .setAccessToken(data.getAccessToken())
+                .setStatus(ChannelAuthStatusEnum.SUCCESS.getCode());
+        fillReturnPath(authResult, session);
+        authSessionStore.writeResultByQueryCode(param.getQueryCode(), session, authResult);
+        return authResult;
+    }
+
+    /// 加载平台级公众号应用(从微信主数据)
+    ///
+    /// 通过 JSAPI 能力推导 OFFICIAL_ACCOUNT 类型, 从 wx_platform_app 主数据查找唯一平台应用。
+    /// 找不到应用时 facade 会抛 appNotConfigured; appSecret 未配置时本方法补充检查。
+    private WxAppView loadPlatformAppOrThrow() {
+        WxAppView app = wxAppFacade.resolve(null, null,
+                PayCapabilityEnum.WECHAT_JSAPI.getCode(), null,
+                ProductEnum.WECHAT_PAY.getCode());
+        if (StrUtil.isBlank(app.appSecret())) {
+            // 微信: 平台级公众号应用授权密钥未配置
+            throw new BizInfoException(CommonErrorCode.SYSTEM_ERROR,
+                    "error.payment.wx.appNotConfigured", "official_account");
+        }
+        return app;
+    }
+}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/strategy/auth/AlipayAuthStrategy.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/strategy/auth/AlipayAuthStrategy.java
deleted file mode 100644
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/strategy/auth/AlipayAuthStrategy.java
+++ /dev/null
@@ -1,49 +0,0 @@
-package cn.daxpay.open.payment.strategy.auth;
-
-import cn.daxpay.open.payment.auth.AuthSession;
-import cn.daxpay.open.payment.auth.PlatformAuthService;
-import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
-import cn.daxpay.open.payment.unipay.param.assist.GenerateAuthUrlParam;
-import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
-import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
-import cn.daxpay.open.platform.core.enums.pay.channel.ProductEnum;
-import lombok.RequiredArgsConstructor;
-import lombok.extern.slf4j.Slf4j;
-import org.springframework.stereotype.Service;
-
-/// # 支付宝通道认证策略
-///
-/// 支付宝直连模式(ALIPAY)下获取用户标识(userId)。与微信策略不同, 支付宝认证不依赖商户级配置,
-/// 统一使用**平台级**支付宝配置, 实现全部委托 [PlatformAuthService], 避免双轨逻辑漂移。
-///
-/// ## 适用场景
-/// - 支付场景获取支付宝 userId(如 ALIPAY_JSAPI 需要)
-/// - 经 [ChannelProductAuthService] 按 product=ALIPAY 路由时的 H5 OAuth / 小程序直连
-///
-/// ## 回调机制
-/// 与微信/抖音策略同构: 回调地址固定为 `{paymentGatewayBaseUrl}/auth/alipay`,
-/// 会话标识 authToken 通过 OAuth state 参数透传(会话由 [ChannelProductAuthService] 管理)。
-@Slf4j
-@Service
-@RequiredArgsConstructor
-public class AlipayAuthStrategy extends AbsChannelAuthStrategy {
-
-    private final PlatformAuthService platformAuthService;
-
-    @Override
-    public ProductEnum getProduct() {
-        return ProductEnum.ALIPAY;
-    }
-
-    /// 生成支付宝授权链接(委托平台服务拼 URL; session/queryCode 已由 ChannelProductAuthService 创建)
-    @Override
-    public AuthUrlResult generateAuthUrl(GenerateAuthUrlParam param, String authToken) {
-        return new AuthUrlResult().setAuthUrl(platformAuthService.buildAlipayAuthUrl(authToken));
-    }
-
-    /// 通过授权 authCode 换取支付宝 userId(委托平台服务, 统一 openId/userId 映射)
-    @Override
-    public AuthResult doAuth(AuthCodeParam param, AuthSession session) {
-        return platformAuthService.authAlipay(param, session);
-    }
-}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/strategy/auth/AuthContext.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/strategy/auth/AuthContext.java
deleted file mode 100644
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/strategy/auth/AuthContext.java
+++ /dev/null
@@ -1,16 +0,0 @@
-package cn.daxpay.open.payment.strategy.auth;
-
-/// # 认证上下文(通道应用定位信息)
-///
-/// 由 [AbsChannelAuthStrategy#resolveContext] 从「session 优先、param 兜底」解析得出,
-/// 供各通道策略在 [AbsChannelAuthStrategy#doAuth] 中定位通道应用(appId/appSecret)。
-///
-/// ## 字段含义
-/// - `channelMchNo`: 通道商户号(定位特约商户主数据 / 反查 mchNo)
-/// - `capability`: 支付能力编码(公众号 / 小程序, 决定应用维度与 openId 类型)
-/// - `channelAppId`: 显式指定的应用 AppId(可选, 优先级高于配置自动解析)
-///
-/// 封装此 record 是为消除各通道策略(WechatIsvAuthStrategy / WechatDirectAuthStrategy / DouyinDirectAuthStrategy)
-/// 在 doAuth 开头重复的「session 字段非空判断 + param 兜底」三段相同代码。
-public record AuthContext(String channelMchNo, String capability, String channelAppId) {
-}
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/trade/runtime/service/pay/gateway/GatewayAuthService.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/trade/runtime/service/pay/gateway/GatewayAuthService.java
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/trade/runtime/service/pay/gateway/GatewayAuthService.java
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/trade/runtime/service/pay/gateway/GatewayAuthService.java
@@ -1,6 +1,6 @@
 package cn.daxpay.open.payment.trade.runtime.service.pay.gateway;
 
-import cn.daxpay.open.payment.auth.ChannelAuthService;
+import cn.daxpay.open.payment.auth.merchant.ChannelAuthService;
 import cn.daxpay.open.payment.merchant.dao.gateway.GatewayCashierItemManager;
 import cn.daxpay.open.payment.merchant.entity.gateway.GatewayCashierItem;
 import cn.daxpay.open.payment.merchant.enums.CashierItemResolveModeEnum;
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/unipay/param/assist/GenerateAuthUrlParam.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/unipay/param/assist/GenerateAuthUrlParam.java
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/unipay/param/assist/GenerateAuthUrlParam.java
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/unipay/param/assist/GenerateAuthUrlParam.java
@@ -22,7 +22,7 @@ public class GenerateAuthUrlParam extends MerchantPaymentCommonParam {
     private String authType = ChannelAuthTypeEnum.WECHAT.getCode();
 
     /// 支付产品编码, 决定走哪个支付产品的认证策略
-    /// 可选: 缺失时由 [cn.daxpay.open.payment.auth.ChannelProductAuthService] 从通道商户号(channelMchNo)反查
+    /// 可选: 缺失时由 [cn.daxpay.open.payment.auth.merchant.ProductAuthService] 从通道商户号(channelMchNo)反查
     /// @see cn.daxpay.open.platform.core.enums.pay.channel.ProductEnum
     @Size(max = 32, message = "{validation.field.product.size}")
     @Schema(description = "支付产品编码")
diff --git a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/unipay/result/assist/AuthUrlResult.java b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/unipay/result/assist/AuthUrlResult.java
--- a/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/unipay/result/assist/AuthUrlResult.java
+++ b/daxpay-payment/daxpay-payment-core/src/main/java/cn/daxpay/open/payment/unipay/result/assist/AuthUrlResult.java
@@ -19,4 +19,11 @@ public class AuthUrlResult {
     @Schema(description = "查询标识码")
     private String queryCode;
 
+    /// 认证会话码(OPEN 场景需据此更新 session 中的 scene/redirect_url)
+    ///
+    /// 由 ProductAuthService / PlatformAuthProvider 在创建 session 后回填,
+    /// 供 OPEN 场景(OpenAuthService)加载并更新会话上下文。
+    @Schema(description = "认证会话码")
+    private String authToken;
+
 }
diff --git a/daxpay-payment/daxpay-payment-merchant/src/main/java/cn/daxpay/open/payment/merchant/controller/develop/MchDevelopAuthController.java b/daxpay-payment/daxpay-payment-merchant/src/main/java/cn/daxpay/open/payment/merchant/controller/develop/MchDevelopAuthController.java
--- a/daxpay-payment/daxpay-payment-merchant/src/main/java/cn/daxpay/open/payment/merchant/controller/develop/MchDevelopAuthController.java
+++ b/daxpay-payment/daxpay-payment-merchant/src/main/java/cn/daxpay/open/payment/merchant/controller/develop/MchDevelopAuthController.java
@@ -1,6 +1,6 @@
 package cn.daxpay.open.payment.merchant.controller.develop;
 
-import cn.daxpay.open.payment.auth.DevelopAuthService;
+import cn.daxpay.open.payment.auth.develop.DevelopAuthService;
 import cn.daxpay.open.payment.unipay.param.assist.GenerateAuthUrlParam;
 import cn.daxpay.open.payment.unipay.result.assist.AuthResult;
 import cn.daxpay.open.payment.unipay.result.assist.AuthUrlResult;
@@ -66,7 +66,7 @@ public Result<AuthUrlResult> generateDouyinAuthUrl() {
     @PostMapping("/generate-channel-auth-url")
     public Result<AuthUrlResult> generateChannelAuthUrl(@RequestBody GenerateAuthUrlParam param) {
         // 不加 @Valid: GenerateAuthUrlParam 继承 PaymentCommonParam.reqTime(@NotNull), 但认证不走签名/防重放, 无需 reqTime;
-        // channel/mchNo 由 ChannelProductAuthService 业务层兜底校验, 与 unipay ChannelAuthController 同类接口保持一致
+        // channel/mchNo 由 ProductAuthService 业务层兜底校验, 与 unipay ChannelAuthController 同类接口保持一致
         return Res.ok(developAuthService.generateChannelAuthUrl(param));
     }
 
diff --git a/daxpay-payment/daxpay-payment-unipay/src/main/java/cn/daxpay/open/payment/unipay/client/controller/GatewayClientController.java b/daxpay-payment/daxpay-payment-unipay/src/main/java/cn/daxpay/open/payment/unipay/client/controller/GatewayClientController.java
--- a/daxpay-payment/daxpay-payment-unipay/src/main/java/cn/daxpay/open/payment/unipay/client/controller/GatewayClientController.java
+++ b/daxpay-payment/daxpay-payment-unipay/src/main/java/cn/daxpay/open/payment/unipay/client/controller/GatewayClientController.java
@@ -80,7 +80,7 @@ public Result<NormalPayResult> cashierPay(@RequestBody @Validated CashierPayPara
         return Res.ok(cashierPayService.pay(param));
     }
 
-    @Operation(summary = "网关 H5 生成授权链接(取 openId, 无商户签名)")
+    @Operation(summary = "网关H5生成授权链接")
     @PostMapping("/auth/generate-url")
     public Result<AuthUrlResult> generateAuthUrl(@RequestBody @Validated GatewayAuthUrlParam param) {
         return Res.ok(gatewayAuthService.generateAuthUrl(param));
diff --git a/daxpay-payment/daxpay-payment-unipay/src/main/java/cn/daxpay/open/payment/unipay/trade/controller/ChannelAuthController.java b/daxpay-payment/daxpay-payment-unipay/src/main/java/cn/daxpay/open/payment/unipay/trade/controller/ChannelAuthController.java
--- a/daxpay-payment/daxpay-payment-unipay/src/main/java/cn/daxpay/open/payment/unipay/trade/controller/ChannelAuthController.java
+++ b/daxpay-payment/daxpay-payment-unipay/src/main/java/cn/daxpay/open/payment/unipay/trade/controller/ChannelAuthController.java
@@ -3,7 +3,7 @@
 import cn.daxpay.open.platform.core.annotation.IgnoreAuth;
 import cn.daxpay.open.platform.core.rest.Res;
 import cn.daxpay.open.platform.core.rest.result.Result;
-import cn.daxpay.open.payment.auth.ChannelAuthService;
+import cn.daxpay.open.payment.auth.merchant.ChannelAuthService;
 import cn.daxpay.open.payment.unipay.param.assist.AuthCodeParam;
 import cn.daxpay.open.payment.unipay.param.assist.GenerateAuthUrlParam;
 import cn.daxpay.open.payment.common.result.DaxResult;
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
