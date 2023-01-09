class LuaNginxModule < Formula
  desc "Embed the power of Lua into Nginx"
  homepage "https://github.com/openresty/lua-nginx-module"
  url "https://github.com/openresty/lua-nginx-module/archive/v0.10.22.tar.gz"
  sha256 "294d3d4b2d14fda1b8c539ff86f90047d203df861eb9a1ac44ec5c679ef55408"
  head "https://github.com/openresty/lua-nginx-module.git", branch: "master"

  depends_on "luajit"
  depends_on "ngx-devel-kit"

  def install
    pkgshare.install Dir["*"]
  end

  def post_install
    # configure script tries to write that file and fails
    # seems to be empty anyways, this hack makes compile succeed
    system "touch",  "#{pkgshare}/src/ngx_http_lua_autoconf.h"
  end
end

__END__
diff --git a/src/ngx_http_lua_headers_in.c b/src/ngx_http_lua_headers_in.c
index 7626d1f..3cee14b 100644
--- a/src/ngx_http_lua_headers_in.c
+++ b/src/ngx_http_lua_headers_in.c
@@ -152,9 +152,15 @@ static ngx_http_lua_set_header_t  ngx_http_lua_set_handlers[] = {
                  ngx_http_set_builtin_header },
 #endif
 
+#if defined(nginx_version) && nginx_version >= 1023000
+    { ngx_string("Cookie"),
+                 offsetof(ngx_http_headers_in_t, cookie),
+                 ngx_http_set_builtin_multi_header },
+#else
     { ngx_string("Cookie"),
                  offsetof(ngx_http_headers_in_t, cookies),
                  ngx_http_set_builtin_multi_header },
+#endif
 
     { ngx_null_string, 0, ngx_http_set_header }
 };
@@ -580,6 +586,45 @@ static ngx_int_t
 ngx_http_set_builtin_multi_header(ngx_http_request_t *r,
     ngx_http_lua_header_val_t *hv, ngx_str_t *value)
 {
+#if defined(nginx_version) && nginx_version >= 1023000
+    ngx_table_elt_t  **headers, **ph, *h;
+    int                nelts;
+
+    headers = (ngx_table_elt_t **) ((char *) &r->headers_in + hv->offset);
+
+    if (!hv->no_override && *headers != NULL) {
+        nelts = 0;
+        for (h = *headers; h; h = h->next) {
+            nelts++;
+        }
+
+        *headers = NULL;
+
+        dd("clear multi-value headers: %d", nelts);
+    }
+
+    if (ngx_http_set_header_helper(r, hv, value, &h) == NGX_ERROR) {
+        return NGX_ERROR;
+    }
+
+    if (value->len == 0) {
+        return NGX_OK;
+    }
+
+    dd("new multi-value header: %p", h);
+
+    if (*headers) {
+        for (ph = headers; *ph; ph = &(*ph)->next) { /* void */ }
+        *ph = h;
+
+    } else {
+        *headers = h;
+    }
+
+    h->next = NULL;
+
+    return NGX_OK;
+#else
     ngx_array_t       *headers;
     ngx_table_elt_t  **v, *h;
 
@@ -626,6 +671,7 @@ ngx_http_set_builtin_multi_header(ngx_http_request_t *r,
 
     *v = h;
     return NGX_OK;
+#endif
 }
 
 
diff --git a/src/ngx_http_lua_headers_out.c b/src/ngx_http_lua_headers_out.c
index 6e1879c..2dd960f 100644
--- a/src/ngx_http_lua_headers_out.c
+++ b/src/ngx_http_lua_headers_out.c
@@ -311,6 +311,69 @@ static ngx_int_t
 ngx_http_set_builtin_multi_header(ngx_http_request_t *r,
     ngx_http_lua_header_val_t *hv, ngx_str_t *value)
 {
+#if defined(nginx_version) && nginx_version >= 1023000
+    ngx_table_elt_t  **headers, *h, *ho, **ph;
+
+    headers = (ngx_table_elt_t **) ((char *) &r->headers_out + hv->offset);
+
+    if (hv->no_override) {
+        for (h = *headers; h; h = h->next) {
+            if (!h->hash) {
+                h->value = *value;
+                h->hash = hv->hash;
+                return NGX_OK;
+            }
+        }
+
+        goto create;
+    }
+
+    /* override old values (if any) */
+
+    if (*headers) {
+        for (h = (*headers)->next; h; h = h->next) {
+            h->hash = 0;
+            h->value.len = 0;
+        }
+
+        h = *headers;
+
+        h->value = *value;
+
+        if (value->len == 0) {
+            h->hash = 0;
+
+        } else {
+            h->hash = hv->hash;
+        }
+
+        return NGX_OK;
+    }
+
+create:
+
+    for (ph = headers; *ph; ph = &(*ph)->next) { /* void */ }
+
+    ho = ngx_list_push(&r->headers_out.headers);
+    if (ho == NULL) {
+        return NGX_ERROR;
+    }
+
+    ho->value = *value;
+
+    if (value->len == 0) {
+        ho->hash = 0;
+
+    } else {
+        ho->hash = hv->hash;
+    }
+
+    ho->key = hv->key;
+    ho->next = NULL;
+    *ph = ho;
+
+    return NGX_OK;
+#else
     ngx_array_t      *pa;
     ngx_table_elt_t  *ho, **ph;
     ngx_uint_t        i;
@@ -384,6 +447,7 @@ create:
     *ph = ho;
 
     return NGX_OK;
+#endif
 }
 
 
