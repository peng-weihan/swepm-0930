#!/bin/bash
set -euo pipefail
cd /testbed
cat > /tmp/gold.patch <<'__SWEPMV2_GOLD_PATCH_EOF__'
diff --git a/.gitignore b/.gitignore
--- a/.gitignore
+++ b/.gitignore
@@ -7,6 +7,7 @@ __pycache__/
 .tox
 .claude/
 docs/ideas/
+docs/specs/
 .coverage
 .pytest_cache/
 htmlcov/
\ No newline at end of file
diff --git a/fetcher/baseFetcher.py b/fetcher/baseFetcher.py
new file mode 100644
--- /dev/null
+++ b/fetcher/baseFetcher.py
@@ -0,0 +1,98 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     baseFetcher.py
+   Description :   代理源基类
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+import re
+
+
+class BaseFetcher(object):
+    """代理源基类"""
+
+    # ---- 子类必须声明 ----
+    name = ""        # 唯一标识，如 "zdaye"
+    url = ""         # 源网站首页 URL
+
+    # ---- 子类可覆盖 ----
+    enabled = True   # 是否启用，设为 False 可禁用该源
+
+    def fetch(self):
+        """爬取代理，yield "host:port" 字符串"""
+        raise NotImplementedError
+
+    @staticmethod
+    def parseProxiesFromText(text):
+        """从文本中用正则提取 ip:port"""
+        if not text:
+            return []
+        proxy_pattern = re.compile(
+            r'(?<![\d.])(\d{1,3}(?:\.\d{1,3}){3})(?:\s*:\s*|\s+)(\d{2,5})(?!\d)')
+        return ["%s:%s" % proxy for proxy in proxy_pattern.findall(text)]
+
+    @staticmethod
+    def parseProxiesFromJson(data):
+        """从 JSON 结构中递归提取 ip:port"""
+        proxies = []
+        if isinstance(data, dict):
+            proxy = data.get("proxy") or data.get("addr") or data.get("address")
+            if proxy:
+                proxies.extend(BaseFetcher.parseProxiesFromText(str(proxy)))
+
+            ip = data.get("ip") or data.get("host") or data.get("server")
+            port = data.get("port")
+            if ip and port:
+                proxies.append("%s:%s" % (ip, port))
+
+            parsed_keys = {"proxy", "addr", "address", "ip", "host", "server", "port"}
+            for key, value in data.items():
+                if key in parsed_keys:
+                    continue
+                proxies.extend(BaseFetcher.parseProxiesFromJson(value))
+        elif isinstance(data, list):
+            for item in data:
+                proxies.extend(BaseFetcher.parseProxiesFromJson(item))
+        elif isinstance(data, str):
+            proxies.extend(BaseFetcher.parseProxiesFromText(data))
+        return proxies
+
+    @staticmethod
+    def parseProxiesFromTree(tree):
+        """从 lxml tree 的 table 行中提取 ip:port"""
+        proxies = []
+        if tree is None:
+            return proxies
+        for tr in tree.xpath("//tr"):
+            cells = [" ".join(td.xpath(".//text()")).strip() for td in tr.xpath("./td")]
+            if len(cells) < 2:
+                continue
+            ip = ""
+            port = ""
+            for cell in cells:
+                ip_match = re.search(r'\d{1,3}(?:\.\d{1,3}){3}', cell)
+                port_match = re.search(r'\b\d{2,5}\b', cell)
+                if ip_match and not ip:
+                    ip = ip_match.group()
+                    continue
+                if port_match and not port:
+                    port = port_match.group()
+            if ip and port:
+                proxies.append("%s:%s" % (ip, port))
+        return proxies
+
+    @staticmethod
+    def yieldUniqueProxies(proxies):
+        """去重 yield"""
+        seen = set()
+        for proxy in proxies:
+            if proxy not in seen:
+                seen.add(proxy)
+                yield proxy
\ No newline at end of file
diff --git a/fetcher/proxyFetcher.py b/fetcher/proxyFetcher.py
deleted file mode 100644
--- a/fetcher/proxyFetcher.py
+++ /dev/null
@@ -1,404 +0,0 @@
-# -*- coding: utf-8 -*-
-"""
--------------------------------------------------
-   File Name：     proxyFetcher
-   Description :
-   Author :        JHao
-   date：          2016/11/25
--------------------------------------------------
-   Change Activity:
-                   2016/11/25: proxyFetcher
--------------------------------------------------
-"""
-__author__ = 'JHao'
-
-import re
-import json
-from time import sleep
-
-from lxml import etree
-
-from util.webRequest import WebRequest
-
-
-class ProxyFetcher(object):
-    """
-    proxy getter
-    """
-
-    @staticmethod
-    def _parse_proxies_from_text(text):
-        if not text:
-            return []
-        proxy_pattern = re.compile(r'(?<![\d.])(\d{1,3}(?:\.\d{1,3}){3})(?:\s*:\s*|\s+)(\d{2,5})(?!\d)')
-        return ["%s:%s" % proxy for proxy in proxy_pattern.findall(text)]
-
-    @staticmethod
-    def _parse_proxies_from_json(data):
-        proxies = []
-        if isinstance(data, dict):
-            proxy = data.get("proxy") or data.get("addr") or data.get("address")
-            if proxy:
-                proxies.extend(ProxyFetcher._parse_proxies_from_text(str(proxy)))
-
-            ip = data.get("ip") or data.get("host") or data.get("server")
-            port = data.get("port")
-            if ip and port:
-                proxies.append("%s:%s" % (ip, port))
-
-            parsed_keys = {"proxy", "addr", "address", "ip", "host", "server", "port"}
-            for key, value in data.items():
-                if key in parsed_keys:
-                    continue
-                proxies.extend(ProxyFetcher._parse_proxies_from_json(value))
-        elif isinstance(data, list):
-            for item in data:
-                proxies.extend(ProxyFetcher._parse_proxies_from_json(item))
-        elif isinstance(data, str):
-            proxies.extend(ProxyFetcher._parse_proxies_from_text(data))
-        return proxies
-
-    @staticmethod
-    def _parse_proxies_from_tree(tree):
-        proxies = []
-        if tree is None:
-            return proxies
-        for tr in tree.xpath("//tr"):
-            cells = [" ".join(td.xpath(".//text()")).strip() for td in tr.xpath("./td")]
-            if len(cells) < 2:
-                continue
-            ip = ""
-            port = ""
-            for cell in cells:
-                ip_match = re.search(r'\d{1,3}(?:\.\d{1,3}){3}', cell)
-                port_match = re.search(r'\b\d{2,5}\b', cell)
-                if ip_match and not ip:
-                    ip = ip_match.group()
-                    continue
-                if port_match and not port:
-                    port = port_match.group()
-            if ip and port:
-                proxies.append("%s:%s" % (ip, port))
-        return proxies
-
-    @staticmethod
-    def _yield_unique_proxies(proxies):
-        seen = set()
-        for proxy in proxies:
-            if proxy not in seen:
-                seen.add(proxy)
-                yield proxy
-
-    @staticmethod
-    def freeProxy01():
-        """
-        站大爷 https://www.zdaye.com/dayProxy.html
-        """
-        start_url = "https://www.zdaye.com/free/"
-        html_tree = WebRequest().get(start_url, verify=False).tree
-        latest_page_time = html_tree.xpath("//span[@class='thread_time_info']/text()")[0].strip()
-        from datetime import datetime
-        interval = datetime.now() - datetime.strptime(latest_page_time, "%Y/%m/%d %H:%M:%S")
-        if interval.seconds < 300:  # 只采集5分钟内的更新
-            target_url = "https://www.zdaye.com/" + html_tree.xpath("//h3[@class='thread_title']/a/@href")[0].strip()
-            while target_url:
-                _tree = WebRequest().get(target_url, verify=False).tree
-                for tr in _tree.xpath("//table//tr"):
-                    ip = "".join(tr.xpath("./td[1]/text()")).strip()
-                    port = "".join(tr.xpath("./td[2]/text()")).strip()
-                    yield "%s:%s" % (ip, port)
-                next_page = _tree.xpath("//div[@class='page']/a[@title='下一页']/@href")
-                target_url = "https://www.zdaye.com/" + next_page[0].strip() if next_page else False
-                sleep(5)
-
-    @staticmethod
-    def freeProxy02():
-        """
-        代理66 http://www.66ip.cn/
-        """
-        url = "http://www.66ip.cn/"
-        resp = WebRequest().get(url, timeout=10).tree
-        for i, tr in enumerate(resp.xpath("(//table)[3]//tr")):
-            if i > 0:
-                ip = "".join(tr.xpath("./td[1]/text()")).strip()
-                port = "".join(tr.xpath("./td[2]/text()")).strip()
-                yield "%s:%s" % (ip, port)
-
-    @staticmethod
-    def freeProxy03():
-        """ 开心代理 """
-        target_urls = ["http://www.kxdaili.com/dailiip.html", "http://www.kxdaili.com/dailiip/2/1.html"]
-        for url in target_urls:
-            tree = WebRequest().get(url).tree
-            for tr in tree.xpath("//table[@class='active']//tr")[1:]:
-                ip = "".join(tr.xpath('./td[1]/text()')).strip()
-                port = "".join(tr.xpath('./td[2]/text()')).strip()
-                yield "%s:%s" % (ip, port)
-
-    @staticmethod
-    def freeProxy04():
-        """ FreeProxyList https://www.freeproxylists.net/zh/ """
-        url = "https://www.freeproxylists.net/zh/?c=CN&pt=&pr=&a%5B%5D=0&a%5B%5D=1&a%5B%5D=2&u=50"
-        tree = WebRequest().get(url, verify=False).tree
-        from urllib import parse
-
-        def parse_ip(input_str):
-            html_str = parse.unquote(input_str)
-            ips = re.findall(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', html_str)
-            return ips[0] if ips else None
-
-        for tr in tree.xpath("//tr[@class='Odd']") + tree.xpath("//tr[@class='Even']"):
-            ip = parse_ip("".join(tr.xpath('./td[1]/script/text()')).strip())
-            port = "".join(tr.xpath('./td[2]/text()')).strip()
-            if ip:
-                yield "%s:%s" % (ip, port)
-
-    @staticmethod
-    def freeProxy05(page_count=1):
-        """ 快代理 https://www.kuaidaili.com """
-        url_pattern = [
-            'https://www.kuaidaili.com/free/inha/{}/',
-            'https://www.kuaidaili.com/free/intr/{}/'
-        ]
-        url_list = []
-        for page_index in range(1, page_count + 1):
-            for pattern in url_pattern:
-                url_list.append(pattern.format(page_index))
-
-        for url in url_list:
-            tree = WebRequest().get(url).tree
-            proxy_list = tree.xpath('.//table//tr')
-            sleep(1)  # 必须sleep 不然第二条请求不到数据
-            for tr in proxy_list[1:]:
-                yield ':'.join(tr.xpath('./td/text()')[0:2])
-
-    @staticmethod
-    def freeProxy06():
-        """ 冰凌代理 https://www.binglx.cn """
-        url = "https://www.binglx.cn/?page=1"
-        try:
-            tree = WebRequest().get(url).tree
-            proxy_list = tree.xpath('.//table//tr')
-            for tr in proxy_list[1:]:
-                yield ':'.join(tr.xpath('./td/text()')[0:2])
-        except Exception as e:
-            print(e)
-
-    @staticmethod
-    def freeProxy07():
-        """ 云代理 """
-        urls = ['http://www.ip3366.net/free/?stype=1', "http://www.ip3366.net/free/?stype=2"]
-        for url in urls:
-            r = WebRequest().get(url, timeout=10)
-            proxies = re.findall(r'<td>(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})</td>[\s\S]*?<td>(\d+)</td>', r.text)
-            for proxy in proxies:
-                yield ":".join(proxy)
-
-    @staticmethod
-    def freeProxy08():
-        """ 小幻代理 """
-        request = WebRequest()
-        ti_url = "https://ip.ihuan.me/ti.html"
-        tqdl_url = "https://ip.ihuan.me/tqdl.html"
-        ti_resp = request.get(ti_url, timeout=10, verify=False)
-        form_data = {}
-        if ti_resp.tree is not None:
-            for input_tag in ti_resp.tree.xpath("//form//input[@name]"):
-                name = "".join(input_tag.xpath("./@name")).strip()
-                value = "".join(input_tag.xpath("./@value")).strip()
-                if name:
-                    form_data[name] = value
-
-        key = form_data.get("key")
-        if not key:
-            key_match = re.search(r'name=["\']key["\'][^>]*value=["\']([^"\']+)', ti_resp.text)
-            if not key_match:
-                key_match = re.search(r'key["\']?\s*[:=]\s*["\']([0-9a-f]{16,})', ti_resp.text)
-            key = key_match.group(1) if key_match else ""
-
-        if not key:
-            return
-
-        header = {
-            "Origin": "https://ip.ihuan.me",
-            "Referer": ti_url,
-        }
-        data = form_data.copy()
-        data.update({
-            "num": "2000",
-            "port": "",
-            "kill_port": "",
-            "address": "",
-            "kill_address": "",
-            "anonymity": "",
-            "type": "",
-            "post": "",
-            "sort": "1",
-            "key": key,
-        })
-        r = request.post(tqdl_url, header=header, data=data, timeout=10, verify=False)
-        proxies = ProxyFetcher._parse_proxies_from_tree(r.tree)
-        proxies.extend(ProxyFetcher._parse_proxies_from_text(r.text))
-        for proxy in ProxyFetcher._yield_unique_proxies(proxies):
-            yield proxy
-
-    @staticmethod
-    def freeProxy09(page_count=1):
-        """ 免费代理库 """
-        for i in range(1, page_count + 1):
-            url = 'http://ip.jiangxianli.com/?country=中国&page={}'.format(i)
-            html_tree = WebRequest().get(url, verify=False).tree
-            for index, tr in enumerate(html_tree.xpath("//table//tr")):
-                if index == 0:
-                    continue
-                yield ":".join(tr.xpath("./td/text()")[0:2]).strip()
-
-    @staticmethod
-    def freeProxy10():
-        """ 89免费代理 """
-        r = WebRequest().get("https://www.89ip.cn/index_1.html", timeout=10)
-        proxies = re.findall(
-            r'<td.*?>[\s\S]*?(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})[\s\S]*?</td>[\s\S]*?<td.*?>[\s\S]*?(\d+)[\s\S]*?</td>',
-            r.text)
-        for proxy in proxies:
-            yield ':'.join(proxy)
-
-    @staticmethod
-    def freeProxy11():
-        """ 稻壳代理 https://www.docip.net/ """
-        r = WebRequest().get("https://www.docip.net/data/free.json", timeout=10)
-        try:
-            for each in r.json['data']:
-                yield each['ip']
-        except Exception as e:
-            print(e)
-
-    @staticmethod
-    def freeProxy12():
-        """ 谷德代理 https://www.goodips.com/ """
-        url = "https://www.goodips.com/"
-        tree = WebRequest().get(url, verify=False).tree
-        for item in tree.xpath("//div[@class='table-list']"):
-            ip = "".join(item.xpath("./ul/li[1]/text()")).strip()
-            port = "".join(item.xpath("./ul/li[2]/text()")).strip()
-            if ip and port:
-                yield "%s:%s" % (ip, port)
-
-    @staticmethod
-    def freeProxy13():
-        """ FreeVPNNode 中国代理 https://cn.freevpnnode.com/free-proxy-for-china/ """
-        # url = "https://cn.freevpnnode.com/free-proxy-for-china/"
-        url = "https://cn.freevpnnode.com/free-proxy/"
-        r = WebRequest().get(url, timeout=5, retry_time=1, verify=False)
-        proxies = ProxyFetcher._parse_proxies_from_tree(r.tree)
-        proxies.extend(ProxyFetcher._parse_proxies_from_text(r.text))
-        for proxy in ProxyFetcher._yield_unique_proxies(proxies):
-            yield proxy
-
-    @staticmethod
-    def freeProxy14():
-        """ SCDN 代理接口 """
-        # url = "https://proxy.scdn.io/get_proxies.php?protocol=&country=%E4%B8%AD%E5%9B%BD&per_page=100&page=1"
-        url = "https://proxy.scdn.io/get_proxies.php?protocol=&country=&per_page=100&page=1"
-        r = WebRequest().get(url, timeout=5, retry_time=1, verify=False)
-        try:
-            data = r.json
-            proxies = []
-            table_html = data.get("table_html") if isinstance(data, dict) else ""
-            if table_html:
-                tree = etree.HTML("<table>%s</table>" % table_html)
-                proxies.extend(ProxyFetcher._parse_proxies_from_tree(tree))
-
-            if not proxies:
-                proxies = ProxyFetcher._parse_proxies_from_json(data)
-            if not proxies:
-                proxies = ProxyFetcher._parse_proxies_from_text(r.text)
-            for proxy in ProxyFetcher._yield_unique_proxies(proxies):
-                yield proxy
-        except Exception as e:
-            print(e)
-
-    @staticmethod
-    def freeProxy15():
-        """ Geonode Free Proxy 中国代理 https://geonode.com/free-proxy-list/ """
-        # url = "https://proxylist.geonode.com/api/proxy-list?limit=500&page=1&sort_by=lastChecked&sort_type=desc&country=CN"
-        url = "https://proxylist.geonode.com/api/proxy-list?limit=500&page=1&sort_by=lastChecked&sort_type=desc"
-        r = WebRequest().get(url, timeout=5, retry_time=1, verify=False)
-        try:
-            proxies = ProxyFetcher._parse_proxies_from_json(r.json)
-            if not proxies:
-                proxies = ProxyFetcher._parse_proxies_from_text(r.text)
-            for proxy in ProxyFetcher._yield_unique_proxies(proxies):
-                yield proxy
-        except Exception as e:
-            print(e)
-
-    # @staticmethod
-    # def wallProxy01():
-    #     """
-    #     PzzQz https://pzzqz.com/
-    #     """
-    #     from requests import Session
-    #     from lxml import etree
-    #     session = Session()
-    #     try:
-    #         index_resp = session.get("https://pzzqz.com/", timeout=20, verify=False).text
-    #         x_csrf_token = re.findall('X-CSRFToken": "(.*?)"', index_resp)
-    #         if x_csrf_token:
-    #             data = {"http": "on", "ping": "3000", "country": "cn", "ports": ""}
-    #             proxy_resp = session.post("https://pzzqz.com/", verify=False,
-    #                                       headers={"X-CSRFToken": x_csrf_token[0]}, json=data).json()
-    #             tree = etree.HTML(proxy_resp["proxy_html"])
-    #             for tr in tree.xpath("//tr"):
-    #                 ip = "".join(tr.xpath("./td[1]/text()"))
-    #                 port = "".join(tr.xpath("./td[2]/text()"))
-    #                 yield "%s:%s" % (ip, port)
-    #     except Exception as e:
-    #         print(e)
-
-    # @staticmethod
-    # def freeProxy10():
-    #     """
-    #     墙外网站 cn-proxy
-    #     :return:
-    #     """
-    #     urls = ['http://cn-proxy.com/', 'http://cn-proxy.com/archives/218']
-    #     request = WebRequest()
-    #     for url in urls:
-    #         r = request.get(url, timeout=10)
-    #         proxies = re.findall(r'<td>(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})</td>[\w\W]<td>(\d+)</td>', r.text)
-    #         for proxy in proxies:
-    #             yield ':'.join(proxy)
-
-    # @staticmethod
-    # def freeProxy11():
-    #     """
-    #     https://proxy-list.org/english/index.php
-    #     :return:
-    #     """
-    #     urls = ['https://proxy-list.org/english/index.php?p=%s' % n for n in range(1, 10)]
-    #     request = WebRequest()
-    #     import base64
-    #     for url in urls:
-    #         r = request.get(url, timeout=10)
-    #         proxies = re.findall(r"Proxy\('(.*?)'\)", r.text)
-    #         for proxy in proxies:
-    #             yield base64.b64decode(proxy).decode()
-
-    # @staticmethod
-    # def freeProxy12():
-    #     urls = ['https://list.proxylistplus.com/Fresh-HTTP-Proxy-List-1']
-    #     request = WebRequest()
-    #     for url in urls:
-    #         r = request.get(url, timeout=10)
-    #         proxies = re.findall(r'<td>(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})</td>[\s\S]*?<td>(\d+)</td>', r.text)
-    #         for proxy in proxies:
-    #             yield ':'.join(proxy)
-
-
-if __name__ == '__main__':
-    p = ProxyFetcher()
-    for _ in p.freeProxy12():
-        print(_)
-
-# http://nntime.com/proxy-list-01.htm
diff --git a/fetcher/sources/__init__.py b/fetcher/sources/__init__.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/__init__.py
@@ -0,0 +1,13 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     __init__.py
+   Description :   代理源目录
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
\ No newline at end of file
diff --git a/fetcher/sources/binglx.py b/fetcher/sources/binglx.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/binglx.py
@@ -0,0 +1,38 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     binglx.py
+   Description :   冰凌代理代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class BinglxFetcher(BaseFetcher):
+    """冰凌代理 https://www.binglx.cn"""
+
+    name = "binglx"
+    url = "https://www.binglx.cn/"
+
+    def fetch(self):
+        url = "https://www.binglx.cn/?page=1"
+        try:
+            tree = WebRequest().get(url).tree
+            proxy_list = tree.xpath('.//table//tr')
+            for tr in proxy_list[1:]:
+                yield ':'.join(tr.xpath('./td/text()')[0:2])
+        except Exception as e:
+            print(e)
+
+
+if __name__ == '__main__':
+    for proxy in BinglxFetcher().fetch():
+        print(proxy)
\ No newline at end of file
diff --git a/fetcher/sources/docip.py b/fetcher/sources/docip.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/docip.py
@@ -0,0 +1,36 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     docip.py
+   Description :   稻壳代理代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class DocipFetcher(BaseFetcher):
+    """稻壳代理 https://www.docip.net/"""
+
+    name = "docip"
+    url = "https://www.docip.net/"
+
+    def fetch(self):
+        r = WebRequest().get("https://www.docip.net/data/free.json", timeout=10)
+        try:
+            for each in r.json['data']:
+                yield each['ip']
+        except Exception as e:
+            print(e)
+
+
+if __name__ == '__main__':
+    for proxy in DocipFetcher().fetch():
+        print(proxy)
\ No newline at end of file
diff --git a/fetcher/sources/freeproxylist.py b/fetcher/sources/freeproxylist.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/freeproxylist.py
@@ -0,0 +1,47 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     freeproxylist.py
+   Description :   FreeProxyList代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+import re
+from urllib import parse
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class FreeProxyListFetcher(BaseFetcher):
+    """FreeProxyList https://www.freeproxylists.net/zh/"""
+
+    name = "freeproxylist"
+    url = "https://www.freeproxylists.net/zh/"
+
+    @staticmethod
+    def _parse_ip(input_str):
+        html_str = parse.unquote(input_str)
+        ips = re.findall(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', html_str)
+        return ips[0] if ips else None
+
+    def fetch(self):
+        url = ("https://www.freeproxylists.net/zh/"
+               "?c=CN&pt=&pr=&a%5B%5D=0&a%5B%5D=1&a%5B%5D=2&u=50")
+        tree = WebRequest().get(url, verify=False).tree
+        for tr in tree.xpath("//tr[@class='Odd']") + tree.xpath("//tr[@class='Even']"):
+            ip = self._parse_ip("".join(tr.xpath('./td[1]/script/text()')).strip())
+            port = "".join(tr.xpath('./td[2]/text()')).strip()
+            if ip:
+                yield "%s:%s" % (ip, port)
+
+
+if __name__ == '__main__':
+    for proxy in FreeProxyListFetcher().fetch():
+        print(proxy)
diff --git a/fetcher/sources/freevpnnode.py b/fetcher/sources/freevpnnode.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/freevpnnode.py
@@ -0,0 +1,36 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     freevpnnode.py
+   Description :   FreeVPNNode代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class FreeVPNNodeFetcher(BaseFetcher):
+    """FreeVPNNode https://cn.freevpnnode.com/free-proxy/"""
+
+    name = "freevpnnode"
+    url = "https://cn.freevpnnode.com/free-proxy/"
+
+    def fetch(self):
+        url = "https://cn.freevpnnode.com/free-proxy/"
+        r = WebRequest().get(url, timeout=5, retry_time=1, verify=False)
+        proxies = self.parseProxiesFromTree(r.tree)
+        proxies.extend(self.parseProxiesFromText(r.text))
+        for proxy in self.yieldUniqueProxies(proxies):
+            yield proxy
+
+
+if __name__ == '__main__':
+    for proxy in FreeVPNNodeFetcher().fetch():
+        print(proxy)
diff --git a/fetcher/sources/geonode.py b/fetcher/sources/geonode.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/geonode.py
@@ -0,0 +1,41 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     geonode.py
+   Description :   Geonode代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class GeonodeFetcher(BaseFetcher):
+    """Geonode Free Proxy https://geonode.com/free-proxy-list/"""
+
+    name = "geonode"
+    url = "https://geonode.com/free-proxy-list/"
+
+    def fetch(self):
+        url = ("https://proxylist.geonode.com/api/proxy-list?"
+               "limit=500&page=1&sort_by=lastChecked&sort_type=desc")
+        r = WebRequest().get(url, timeout=5, retry_time=1, verify=False)
+        try:
+            proxies = self.parseProxiesFromJson(r.json)
+            if not proxies:
+                proxies = self.parseProxiesFromText(r.text)
+            for proxy in self.yieldUniqueProxies(proxies):
+                yield proxy
+        except Exception as e:
+            print(e)
+
+
+if __name__ == '__main__':
+    for proxy in GeonodeFetcher().fetch():
+        print(proxy)
\ No newline at end of file
diff --git a/fetcher/sources/goodips.py b/fetcher/sources/goodips.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/goodips.py
@@ -0,0 +1,37 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     goodips.py
+   Description :   谷德代理代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class GoodipsFetcher(BaseFetcher):
+    """谷德代理 https://www.goodips.com/"""
+
+    name = "goodips"
+    url = "https://www.goodips.com/"
+
+    def fetch(self):
+        url = "https://www.goodips.com/"
+        tree = WebRequest().get(url, verify=False).tree
+        for item in tree.xpath("//div[@class='table-list']"):
+            ip = "".join(item.xpath("./ul/li[1]/text()")).strip()
+            port = "".join(item.xpath("./ul/li[2]/text()")).strip()
+            if ip and port:
+                yield "%s:%s" % (ip, port)
+
+
+if __name__ == '__main__':
+    for proxy in GoodipsFetcher().fetch():
+        print(proxy)
\ No newline at end of file
diff --git a/fetcher/sources/ihuan.py b/fetcher/sources/ihuan.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/ihuan.py
@@ -0,0 +1,78 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     ihuan.py
+   Description :   小幻代理代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+import re
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class IhuanFetcher(BaseFetcher):
+    """小幻代理 https://ip.ihuan.me/"""
+
+    name = "ihuan"
+    url = "https://ip.ihuan.me/"
+
+    def fetch(self):
+        request = WebRequest()
+        ti_url = "https://ip.ihuan.me/ti.html"
+        tqdl_url = "https://ip.ihuan.me/tqdl.html"
+        ti_resp = request.get(ti_url, timeout=10, verify=False)
+        form_data = {}
+        if ti_resp.tree is not None:
+            for input_tag in ti_resp.tree.xpath("//form//input[@name]"):
+                name = "".join(input_tag.xpath("./@name")).strip()
+                value = "".join(input_tag.xpath("./@value")).strip()
+                if name:
+                    form_data[name] = value
+
+        key = form_data.get("key")
+        if not key:
+            key_match = re.search(
+                r'name=["\']key["\'][^>]*value=["\']([^"\']+)', ti_resp.text)
+            if not key_match:
+                key_match = re.search(
+                    r'key["\']?\s*[:=]\s*["\']([0-9a-f]{16,})', ti_resp.text)
+            key = key_match.group(1) if key_match else ""
+
+        if not key:
+            return
+
+        header = {
+            "Origin": "https://ip.ihuan.me",
+            "Referer": ti_url,
+        }
+        data = form_data.copy()
+        data.update({
+            "num": "2000",
+            "port": "",
+            "kill_port": "",
+            "address": "",
+            "kill_address": "",
+            "anonymity": "",
+            "type": "",
+            "post": "",
+            "sort": "1",
+            "key": key,
+        })
+        r = request.post(tqdl_url, header=header, data=data, timeout=10, verify=False)
+        proxies = self.parseProxiesFromTree(r.tree)
+        proxies.extend(self.parseProxiesFromText(r.text))
+        for proxy in self.yieldUniqueProxies(proxies):
+            yield proxy
+
+
+if __name__ == '__main__':
+    for proxy in IhuanFetcher().fetch():
+        print(proxy)
diff --git a/fetcher/sources/ip3366.py b/fetcher/sources/ip3366.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/ip3366.py
@@ -0,0 +1,43 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     ip3366.py
+   Description :   云代理代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+import re
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class Ip3366Fetcher(BaseFetcher):
+    """云代理 http://www.ip3366.net/"""
+
+    name = "ip3366"
+    url = "http://www.ip3366.net/"
+
+    def fetch(self):
+        urls = [
+            'http://www.ip3366.net/free/?stype=1',
+            "http://www.ip3366.net/free/?stype=2",
+        ]
+        for url in urls:
+            r = WebRequest().get(url, timeout=10)
+            proxies = re.findall(
+                r'<td>(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})</td>[\s\S]*?<td>(\d+)</td>',
+                r.text)
+            for proxy in proxies:
+                yield ":".join(proxy)
+
+
+if __name__ == '__main__':
+    for proxy in Ip3366Fetcher().fetch():
+        print(proxy)
\ No newline at end of file
diff --git a/fetcher/sources/ip66.py b/fetcher/sources/ip66.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/ip66.py
@@ -0,0 +1,37 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     ip66.py
+   Description :   代理66代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class Ip66Fetcher(BaseFetcher):
+    """代理66 http://www.66ip.cn/"""
+
+    name = "ip66"
+    url = "http://www.66ip.cn/"
+
+    def fetch(self):
+        url = "http://www.66ip.cn/"
+        resp = WebRequest().get(url, timeout=10).tree
+        for i, tr in enumerate(resp.xpath("(//table)[3]//tr")):
+            if i > 0:
+                ip = "".join(tr.xpath("./td[1]/text()")).strip()
+                port = "".join(tr.xpath("./td[2]/text()")).strip()
+                yield "%s:%s" % (ip, port)
+
+
+if __name__ == '__main__':
+    for proxy in Ip66Fetcher().fetch():
+        print(proxy)
diff --git a/fetcher/sources/ip89.py b/fetcher/sources/ip89.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/ip89.py
@@ -0,0 +1,38 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     ip89.py
+   Description :   89免费代理代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+import re
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class Ip89Fetcher(BaseFetcher):
+    """89免费代理 https://www.89ip.cn/"""
+
+    name = "ip89"
+    url = "https://www.89ip.cn/"
+
+    def fetch(self):
+        r = WebRequest().get("https://www.89ip.cn/index_1.html", timeout=10)
+        proxies = re.findall(
+            r'<td.*?>[\s\S]*?(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})[\s\S]*?</td>[\s\S]*?<td.*?>[\s\S]*?(\d+)[\s\S]*?</td>',
+            r.text)
+        for proxy in proxies:
+            yield ':'.join(proxy)
+
+
+if __name__ == '__main__':
+    for proxy in Ip89Fetcher().fetch():
+        print(proxy)
\ No newline at end of file
diff --git a/fetcher/sources/jiangxianli.py b/fetcher/sources/jiangxianli.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/jiangxianli.py
@@ -0,0 +1,37 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     jiangxianli.py
+   Description :   免费代理库代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class JiangxianliFetcher(BaseFetcher):
+    """免费代理库 http://ip.jiangxianli.com/"""
+
+    name = "jiangxianli"
+    url = "http://ip.jiangxianli.com/"
+
+    def fetch(self, page_count=1):
+        for i in range(1, page_count + 1):
+            url = 'http://ip.jiangxianli.com/?country=中国&page={}'.format(i)
+            html_tree = WebRequest().get(url, verify=False).tree
+            for index, tr in enumerate(html_tree.xpath("//table//tr")):
+                if index == 0:
+                    continue
+                yield ":".join(tr.xpath("./td/text()")[0:2]).strip()
+
+
+if __name__ == '__main__':
+    for proxy in JiangxianliFetcher().fetch():
+        print(proxy)
diff --git a/fetcher/sources/kuaidaili.py b/fetcher/sources/kuaidaili.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/kuaidaili.py
@@ -0,0 +1,47 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     kuaidaili.py
+   Description :   快代理代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from time import sleep
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class KuaidailiFetcher(BaseFetcher):
+    """快代理 https://www.kuaidaili.com"""
+
+    name = "kuaidaili"
+    url = "https://www.kuaidaili.com"
+
+    def fetch(self, page_count=1):
+        url_pattern = [
+            'https://www.kuaidaili.com/free/inha/{}/',
+            'https://www.kuaidaili.com/free/intr/{}/',
+        ]
+        url_list = []
+        for page_index in range(1, page_count + 1):
+            for pattern in url_pattern:
+                url_list.append(pattern.format(page_index))
+
+        for url in url_list:
+            tree = WebRequest().get(url).tree
+            proxy_list = tree.xpath('.//table//tr')
+            sleep(1)  # 必须sleep 不然第二条请求不到数据
+            for tr in proxy_list[1:]:
+                yield ':'.join(tr.xpath('./td/text()')[0:2])
+
+
+if __name__ == '__main__':
+    for proxy in KuaidailiFetcher().fetch():
+        print(proxy)
diff --git a/fetcher/sources/kxdaili.py b/fetcher/sources/kxdaili.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/kxdaili.py
@@ -0,0 +1,40 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     kxdaili.py
+   Description :   开心代理代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class KxdailiFetcher(BaseFetcher):
+    """开心代理 http://www.kxdaili.com/"""
+
+    name = "kxdaili"
+    url = "http://www.kxdaili.com/dailiip.html"
+
+    def fetch(self):
+        target_urls = [
+            "http://www.kxdaili.com/dailiip.html",
+            "http://www.kxdaili.com/dailiip/2/1.html",
+        ]
+        for url in target_urls:
+            tree = WebRequest().get(url).tree
+            for tr in tree.xpath("//table[@class='active']//tr")[1:]:
+                ip = "".join(tr.xpath('./td[1]/text()')).strip()
+                port = "".join(tr.xpath('./td[2]/text()')).strip()
+                yield "%s:%s" % (ip, port)
+
+
+if __name__ == '__main__':
+    for proxy in KxdailiFetcher().fetch():
+        print(proxy)
diff --git a/fetcher/sources/scdn.py b/fetcher/sources/scdn.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/scdn.py
@@ -0,0 +1,51 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     scdn.py
+   Description :   SCDN代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from lxml import etree
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class ScdnFetcher(BaseFetcher):
+    """SCDN 代理接口 https://proxy.scdn.io/"""
+
+    name = "scdn"
+    url = "https://proxy.scdn.io/"
+
+    def fetch(self):
+        url = ("https://proxy.scdn.io/get_proxies.php?"
+               "protocol=&country=&per_page=100&page=1")
+        r = WebRequest().get(url, timeout=5, retry_time=1, verify=False)
+        try:
+            data = r.json
+            proxies = []
+            table_html = data.get("table_html") if isinstance(data, dict) else ""
+            if table_html:
+                tree = etree.HTML("<table>%s</table>" % table_html)
+                proxies.extend(self.parseProxiesFromTree(tree))
+
+            if not proxies:
+                proxies = self.parseProxiesFromJson(data)
+            if not proxies:
+                proxies = self.parseProxiesFromText(r.text)
+            for proxy in self.yieldUniqueProxies(proxies):
+                yield proxy
+        except Exception as e:
+            print(e)
+
+
+if __name__ == '__main__':
+    for proxy in ScdnFetcher().fetch():
+        print(proxy)
diff --git a/fetcher/sources/zdaye.py b/fetcher/sources/zdaye.py
new file mode 100644
--- /dev/null
+++ b/fetcher/sources/zdaye.py
@@ -0,0 +1,53 @@
+# -*- coding: utf-8 -*-
+"""
+-------------------------------------------------
+   File Name：     zdaye.py
+   Description :   站大爷代理源
+   Author :        JHao
+   date：          2026/5/31
+-------------------------------------------------
+   Change Activity:
+                   2026/05/31:
+-------------------------------------------------
+"""
+__author__ = 'JHao'
+
+from time import sleep
+from datetime import datetime
+
+from fetcher.baseFetcher import BaseFetcher
+from util.webRequest import WebRequest
+
+
+class ZdayeFetcher(BaseFetcher):
+    """站大爷 https://www.zdaye.com/dayProxy.html"""
+
+    name = "zdaye"
+    url = "https://www.zdaye.com/dayProxy.html"
+
+    def fetch(self):
+        start_url = "https://www.zdaye.com/free/"
+        html_tree = WebRequest().get(start_url, verify=False).tree
+        latest_page_time = html_tree.xpath(
+            "//span[@class='thread_time_info']/text()")[0].strip()
+        interval = datetime.now() - datetime.strptime(
+            latest_page_time, "%Y/%m/%d %H:%M:%S")
+        if interval.seconds < 300:
+            target_url = ("https://www.zdaye.com/"
+                          + html_tree.xpath("//h3[@class='thread_title']/a/@href")[0].strip())
+            while target_url:
+                _tree = WebRequest().get(target_url, verify=False).tree
+                for tr in _tree.xpath("//table//tr"):
+                    ip = "".join(tr.xpath("./td[1]/text()")).strip()
+                    port = "".join(tr.xpath("./td[2]/text()")).strip()
+                    yield "%s:%s" % (ip, port)
+                next_page = _tree.xpath(
+                    "//div[@class='page']/a[@title='下一页']/@href")
+                target_url = ("https://www.zdaye.com/" + next_page[0].strip()
+                              if next_page else False)
+                sleep(5)
+
+
+if __name__ == '__main__':
+    for proxy in ZdayeFetcher().fetch():
+        print(proxy)
diff --git a/handler/configHandler.py b/handler/configHandler.py
--- a/handler/configHandler.py
+++ b/handler/configHandler.py
@@ -41,9 +41,9 @@ def tableName(self):
         return os.getenv("TABLE_NAME", setting.TABLE_NAME)
 
     @property
-    def fetchers(self):
+    def fetcherExclude(self):
         reload_six(setting)
-        return setting.PROXY_FETCHER
+        return getattr(setting, 'PROXY_FETCHER_EXCLUDE', [])
 
     @LazyProperty
     def httpUrl(self):
diff --git a/helper/fetch.py b/helper/fetch.py
--- a/helper/fetch.py
+++ b/helper/fetch.py
@@ -1,50 +1,110 @@
 # -*- coding: utf-8 -*-
 """
 -------------------------------------------------
-   File Name：     fetchScheduler
-   Description :
+   File Name：     fetch.py
+   Description :   代理采集
    Author :        JHao
    date：          2019/8/6
 -------------------------------------------------
    Change Activity:
-                   2021/11/18: 多线程采集
+                   2019/08/06: 多线程采集
+                   2026/05/31: 重构为动态加载 fetcher 插件
 -------------------------------------------------
 """
 __author__ = 'JHao'
 
+import os
+import sys
+import importlib
 from threading import Thread
+
 from helper.proxy import Proxy
 from helper.check import DoValidator
 from handler.logHandler import LogHandler
-from handler.proxyHandler import ProxyHandler
-from fetcher.proxyFetcher import ProxyFetcher
 from handler.configHandler import ConfigHandler
+from fetcher.baseFetcher import BaseFetcher
+
+
+def _get_sources_dir():
+    return os.path.join(
+        os.path.dirname(os.path.abspath(__file__)), '..', 'fetcher', 'sources')
+
+
+def _load_fetcher_class(class_name):
+    """
+    动态加载 fetcher 类，支持运行时热更新。
+    每次调用重新 import module，确保读到文件最新版本。
+    """
+    sources_dir = _get_sources_dir()
+    for filename in os.listdir(sources_dir):
+        if not filename.endswith('.py') or filename.startswith('_'):
+            continue
+        module_name = "fetcher.sources.%s" % filename[:-3]
+        try:
+            if module_name in sys.modules:
+                module = importlib.reload(sys.modules[module_name])
+            else:
+                module = importlib.import_module(module_name)
+            fetcher_class = getattr(module, class_name, None)
+            if fetcher_class and issubclass(fetcher_class, BaseFetcher):
+                return fetcher_class
+        except Exception:
+            continue
+    return None
+
+
+def _discover_fetchers(exclude_list):
+    """
+    自动扫描 sources/ 目录，返回所有 enabled=True 且不在黑名单中的 fetcher 类名列表。
+    每次调用重新加载模块，支持运行时热更新。
+    """
+    sources_dir = _get_sources_dir()
+    fetcher_names = []
+    for filename in os.listdir(sources_dir):
+        if not filename.endswith('.py') or filename.startswith('_'):
+            continue
+        module_name = "fetcher.sources.%s" % filename[:-3]
+        try:
+            if module_name in sys.modules:
+                module = importlib.reload(sys.modules[module_name])
+            else:
+                module = importlib.import_module(module_name)
+            for attr_name in dir(module):
+                attr = getattr(module, attr_name, None)
+                if (attr and isinstance(attr, type)
+                        and issubclass(attr, BaseFetcher)
+                        and attr is not BaseFetcher
+                        and attr.name
+                        and attr.enabled
+                        and attr.__name__ not in exclude_list):
+                    fetcher_names.append(attr.__name__)
+        except Exception:
+            continue
+    return sorted(fetcher_names)
 
 
 class _ThreadFetcher(Thread):
 
-    def __init__(self, fetch_source, proxy_dict):
+    def __init__(self, fetcher_class, proxy_dict):
         Thread.__init__(self)
-        self.fetch_source = fetch_source
+        self.fetcher_class = fetcher_class
         self.proxy_dict = proxy_dict
-        self.fetcher = getattr(ProxyFetcher, fetch_source, None)
         self.log = LogHandler("fetcher")
-        self.conf = ConfigHandler()
-        self.proxy_handler = ProxyHandler()
 
     def run(self):
-        self.log.info("ProxyFetch - {func}: start".format(func=self.fetch_source))
+        fetcher_name = self.fetcher_class.name
+        self.log.info("ProxyFetch - {func}: start".format(func=fetcher_name))
         try:
-            for proxy in self.fetcher():
-                self.log.info('ProxyFetch - %s: %s ok' % (self.fetch_source, proxy.ljust(23)))
+            for proxy in self.fetcher_class().fetch():
+                self.log.info('ProxyFetch - %s: %s ok' % (fetcher_name, proxy.ljust(23)))
                 proxy = proxy.strip()
                 if proxy in self.proxy_dict:
-                    self.proxy_dict[proxy].add_source(self.fetch_source)
+                    self.proxy_dict[proxy].add_source(fetcher_name)
                 else:
                     self.proxy_dict[proxy] = Proxy(
-                        proxy, source=self.fetch_source)
+                        proxy, source=fetcher_name)
         except Exception as e:
-            self.log.error("ProxyFetch - {func}: error".format(func=self.fetch_source))
+            self.log.error("ProxyFetch - {func}: error".format(func=fetcher_name))
             self.log.error(str(e))
 
 
@@ -57,23 +117,23 @@ def __init__(self):
 
     def run(self):
         """
-        fetch proxy with proxyFetcher
+        fetch proxy with fetcher plugins
         :return:
         """
         proxy_dict = dict()
         thread_list = list()
         self.log.info("ProxyFetch : start")
 
-        for fetch_source in self.conf.fetchers:
-            self.log.info("ProxyFetch - {func}: start".format(func=fetch_source))
-            fetcher = getattr(ProxyFetcher, fetch_source, None)
-            if not fetcher:
-                self.log.error("ProxyFetch - {func}: class method not exists!".format(func=fetch_source))
-                continue
-            if not callable(fetcher):
-                self.log.error("ProxyFetch - {func}: must be class method".format(func=fetch_source))
+        exclude_list = self.conf.fetcherExclude
+        fetcher_names = _discover_fetchers(exclude_list)
+        self.log.info("ProxyFetch : active fetchers [%s]" % ", ".join(fetcher_names))
+
+        for fetcher_name in fetcher_names:
+            fetcher_class = _load_fetcher_class(fetcher_name)
+            if not fetcher_class:
+                self.log.error("ProxyFetch - {func}: class not exists!".format(func=fetcher_name))
                 continue
-            thread_list.append(_ThreadFetcher(fetch_source, proxy_dict))
+            thread_list.append(_ThreadFetcher(fetcher_class, proxy_dict))
 
         for thread in thread_list:
             thread.setDaemon(True)
diff --git a/helper/launcher.py b/helper/launcher.py
--- a/helper/launcher.py
+++ b/helper/launcher.py
@@ -49,7 +49,10 @@ def __showConfigure():
     conf = ConfigHandler()
     log.info("ProxyPool configure HOST: %s" % conf.serverHost)
     log.info("ProxyPool configure PORT: %s" % conf.serverPort)
-    log.info("ProxyPool configure PROXY_FETCHER: %s" % conf.fetchers)
+    exclude = conf.fetcherExclude
+    if exclude:
+        log.info("ProxyPool configure PROXY_FETCHER_EXCLUDE: %s" % exclude)
+    log.info("ProxyPool configure PROXY_FETCHER: auto-scan (enabled=True, exclude=%s)" % exclude)
 
 
 def __checkDBConfig():
diff --git a/proxyPool.py b/proxyPool.py
--- a/proxyPool.py
+++ b/proxyPool.py
@@ -39,5 +39,20 @@ def server():
     startServer()
 
 
+@cli.command(name="show")
+def show():
+    """ 查看启用的代理源 """
+    from helper.fetch import _discover_fetchers
+    from handler.configHandler import ConfigHandler
+    conf = ConfigHandler()
+    exclude = conf.fetcherExclude
+    fetcher_names = _discover_fetchers(exclude)
+    click.echo("Active fetchers (%d):" % len(fetcher_names))
+    for name in fetcher_names:
+        click.echo("  - %s" % name)
+    if exclude:
+        click.echo("\nExcluded: %s" % ", ".join(exclude))
+
+
 if __name__ == '__main__':
     cli()
diff --git a/setting.py b/setting.py
--- a/setting.py
+++ b/setting.py
@@ -44,23 +44,9 @@
 
 
 # ###### config the proxy fetch function ######
-PROXY_FETCHER = [
-    "freeProxy01",
-    "freeProxy02",
-    "freeProxy03",
-    "freeProxy04",
-    "freeProxy05",
-    "freeProxy06",
-    "freeProxy07",
-    "freeProxy08",
-    "freeProxy09",
-    "freeProxy10",
-    "freeProxy11",
-    "freeProxy12",
-    "freeProxy13",
-    "freeProxy14",
-    "freeProxy15",
-]
+# 自动扫描 fetcher/sources/ 目录，加载所有 enabled=True 的 fetcher
+# 如需临时禁用某个 fetcher，在下方黑名单中添加类名（不改源文件）
+PROXY_FETCHER_EXCLUDE = []
 
 # ############# proxy validator #################
 # 代理验证目标网站
__SWEPMV2_GOLD_PATCH_EOF__
git apply --verbose --whitespace=nowarn /tmp/gold.patch
