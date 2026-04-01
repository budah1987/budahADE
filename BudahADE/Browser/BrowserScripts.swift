import Foundation

/// JavaScript source strings injected into WKWebView instances.
enum BrowserScripts {

    // MARK: - Console Capture

    /// Overrides console.log/warn/error/info/debug and forwards each call to Swift
    /// via window.webkit.messageHandlers.consoleCapture.postMessage({level, text, timestamp}).
    static let consoleCapture = """
    (function() {
      if (window.__budahConsoleHooked) return;
      window.__budahConsoleHooked = true;
      ['log','warn','error','info','debug'].forEach(function(level) {
        var orig = console[level].bind(console);
        console[level] = function() {
          var text = Array.prototype.slice.call(arguments).map(function(a) {
            if (a === null) return 'null';
            if (a === undefined) return 'undefined';
            if (typeof a === 'object') { try { return JSON.stringify(a); } catch(e) { return String(a); } }
            return String(a);
          }).join(' ');
          try { window.webkit.messageHandlers.consoleCapture.postMessage({level:level,text:text,timestamp:Date.now()}); } catch(e) {}
          orig.apply(console, arguments);
        };
      });
    })();
    """

    // MARK: - Network Capture

    /// Wraps window.fetch and XMLHttpRequest to report each request/response to Swift
    /// via window.webkit.messageHandlers.networkCapture.postMessage({url, method, status, duration, timestamp}).
    static let networkCapture = """
    (function() {
      if (window.__budahNetworkHooked) return;
      window.__budahNetworkHooked = true;

      if (typeof window.fetch !== 'undefined') {
        var origFetch = window.fetch.bind(window);
        window.fetch = function(input, init) {
          var url = (input && typeof input === 'object') ? input.url : String(input);
          var method = (init && init.method) ? init.method.toUpperCase() : 'GET';
          var start = Date.now();
          return origFetch(input, init).then(function(resp) {
            try { window.webkit.messageHandlers.networkCapture.postMessage({url:url,method:method,status:resp.status,duration:Date.now()-start,timestamp:start}); } catch(e) {}
            return resp;
          }, function(err) {
            try { window.webkit.messageHandlers.networkCapture.postMessage({url:url,method:method,status:0,error:err.toString(),duration:Date.now()-start,timestamp:start}); } catch(e) {}
            throw err;
          });
        };
      }

      var origXHROpen = XMLHttpRequest.prototype.open;
      var origXHRSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__budahMethod = method.toUpperCase();
        this.__budahURL = url;
        return origXHROpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        var self = this;
        var start = Date.now();
        this.addEventListener('loadend', function() {
          try { window.webkit.messageHandlers.networkCapture.postMessage({url:self.__budahURL||'',method:self.__budahMethod||'GET',status:self.status,duration:Date.now()-start,timestamp:start}); } catch(e) {}
        });
        return origXHRSend.apply(this, arguments);
      };
    })();
    """

    // MARK: - Element Picker

    /// Activates hover-highlight + click-capture mode. On click, posts element context to
    /// window.webkit.messageHandlers.elementPicker.postMessage({selector, html, rect, styles, tagName}).
    /// Esc or post-click deactivates automatically. Sets window.__budahPickerDeactivate for imperative removal.
    static let elementPicker = """
    (function() {
      var highlighted = null;
      var styleEl = document.createElement('style');
      styleEl.id = '__budah_picker_style';
      styleEl.textContent = '.__budah_hl{outline:2px solid #7c6cf0!important;outline-offset:2px!important;cursor:crosshair!important;background-color:rgba(124,108,240,0.08)!important;}';
      document.head.appendChild(styleEl);

      function buildSelector(el) {
        if (el.id) return '#' + CSS.escape(el.id);
        var parts = [];
        var cur = el;
        while (cur && cur !== document.documentElement) {
          var tag = cur.tagName.toLowerCase();
          if (cur.id) { parts.unshift('#' + CSS.escape(cur.id)); break; }
          var cls = Array.from(cur.classList).slice(0,2).map(CSS.escape).join('.');
          parts.unshift(cls ? tag + '.' + cls : tag);
          cur = cur.parentElement;
          if (parts.length >= 5) break;
        }
        return parts.join(' > ');
      }

      function extractStyles(el) {
        var cs = window.getComputedStyle(el);
        var keys = ['color','backgroundColor','fontSize','fontWeight','padding','margin','display','width','height','borderRadius','border','opacity'];
        var r = {};
        keys.forEach(function(k){ r[k] = cs[k]; });
        return r;
      }

      function onOver(e) {
        if (highlighted && highlighted !== e.target) highlighted.classList.remove('__budah_hl');
        highlighted = e.target;
        highlighted.classList.add('__budah_hl');
      }

      function onOut(e) {
        if (highlighted) highlighted.classList.remove('__budah_hl');
      }

      function onClick(e) {
        e.preventDefault(); e.stopPropagation();
        var el = e.target;
        if (highlighted) highlighted.classList.remove('__budah_hl');
        var rect = el.getBoundingClientRect();
        try {
          window.webkit.messageHandlers.elementPicker.postMessage({
            selector: buildSelector(el),
            html: el.outerHTML.substring(0, 2048),
            rect: {x: rect.left, y: rect.top, width: rect.width, height: rect.height},
            styles: extractStyles(el),
            tagName: el.tagName.toLowerCase()
          });
        } catch(e) {}
        deactivate();
      }

      function onKey(e) { if (e.key === 'Escape') deactivate(); }

      function deactivate() {
        if (highlighted) highlighted.classList.remove('__budah_hl');
        var s = document.getElementById('__budah_picker_style');
        if (s) s.remove();
        document.removeEventListener('mouseover', onOver);
        document.removeEventListener('mouseout', onOut);
        document.removeEventListener('click', onClick, true);
        document.removeEventListener('keydown', onKey);
        window.__budahPickerDeactivate = null;
      }

      window.__budahPickerDeactivate = deactivate;
      document.addEventListener('mouseover', onOver);
      document.addEventListener('mouseout', onOut);
      document.addEventListener('click', onClick, true);
      document.addEventListener('keydown', onKey);
    })();
    """
}
