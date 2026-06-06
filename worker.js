// worker.js - Cloudflare Worker for DTech WebSockets using Durable Objects

// This Durable Object manages the WebSocket connection for a specific subdomain
export class TunnelManager {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.activeWebSocket = null;
    this.pendingRequests = new Map();
  }

  async fetch(request) {
    const url = new URL(request.url);

    // 1. App Registration Route (Phone connecting)
    if (url.pathname === '/register') {
      const upgradeHeader = request.headers.get('Upgrade');
      if (!upgradeHeader || upgradeHeader !== 'websocket') {
        return new Response('Expected Upgrade: websocket', { status: 426 });
      }

      // Check simple PSK for security (must match app side)
      const token = url.searchParams.get('token');
      // In a real app, validate token here against a stored secret

      const webSocketPair = new WebSocketPair();
      const [client, server] = Object.values(webSocketPair);

      server.accept();
      this.activeWebSocket = server;

      server.addEventListener('close', () => {
        if (this.activeWebSocket === server) {
          this.activeWebSocket = null;
        }
      });

      server.addEventListener('error', () => {
        if (this.activeWebSocket === server) {
          this.activeWebSocket = null;
        }
      });

      // Handle responses from the phone
      server.addEventListener('message', (event) => {
        try {
          if (typeof event.data === 'string') {
            const parts = event.data.split('|');
            if (parts[0] === 'RES') {
              const reqId = parts[1];
              const statusCode = parseInt(parts[2], 10);
              const headers = JSON.parse(parts[3]);

              if (this.pendingRequests.has(reqId)) {
                // Update the pending request with headers
                const reqState = this.pendingRequests.get(reqId);
                reqState.statusCode = statusCode;
                reqState.headers = headers;
              }
            }
          } else if (event.data instanceof ArrayBuffer) {
            const view = new Uint8Array(event.data);
            const idLength = view[0];
            const idBytes = view.slice(1, 1 + idLength);
            const reqId = new TextDecoder().decode(idBytes);

            if (this.pendingRequests.has(reqId)) {
              const reqState = this.pendingRequests.get(reqId);
              const bodyBytes = view.slice(1 + idLength);

              // Resolve the original promise that's waiting for the response
              reqState.resolve({
                body: bodyBytes.length > 0 ? bodyBytes : null,
                statusCode: reqState.statusCode || 200,
                headers: reqState.headers || {}
              });

              this.pendingRequests.delete(reqId);
            }
          }
        } catch (e) {
          console.error("Error processing message from phone", e);
        }
      });

      return new Response(null, {
        status: 101,
        webSocket: client,
      });
    }

    // 2. Incoming HTTP Traffic Routing (Visitor requesting website)
    if (!this.activeWebSocket) {
      return new Response('Phone is not currently connected to this tunnel.', { status: 502 });
    }

    return new Promise((resolve) => {
      const requestId = crypto.randomUUID();

      // Store state so the websocket listener can resolve it
      this.pendingRequests.set(requestId, {
        resolve: (responseObj) => {
          clearTimeout(timeoutId);
          resolve(new Response(responseObj.body, {
            status: responseObj.statusCode,
            headers: responseObj.headers
          }));
        }
      });

      // Timeout after 30 seconds
      const timeoutId = setTimeout(() => {
        if (this.pendingRequests.has(requestId)) {
          this.pendingRequests.delete(requestId);
          resolve(new Response('Gateway Timeout - Phone took too long to respond', { status: 504 }));
        }
      }, 30000);

      const headersObj = Object.fromEntries(request.headers.entries());
      const reqHeaders = JSON.stringify(headersObj);

      request.text().then(bodyText => {
        const payload = `${requestId}|${request.method}|${url.pathname}${url.search}|${reqHeaders}|${bodyText || ''}`;
        if (this.activeWebSocket) {
          this.activeWebSocket.send(payload);
        } else {
          clearTimeout(timeoutId);
          this.pendingRequests.delete(requestId);
          resolve(new Response('Connection lost', { status: 502 }));
        }
      }).catch(e => {
        clearTimeout(timeoutId);
        this.pendingRequests.delete(requestId);
        resolve(new Response('Error reading request body', { status: 500 }));
      });
    });
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Get the subdomain either from the hostname (visitor) or query param (phone connecting)
    let subdomain = null;

    if (url.pathname === '/register') {
      subdomain = url.searchParams.get('subdomain');
    } else {
      const host = url.hostname;
      const domainParts = host.split('.');
      subdomain = domainParts.length > 2 ? domainParts[0] : null;
    }

    if (!subdomain) {
      return new Response('Direct access not allowed. Please use a valid subdomain.', { status: 400 });
    }

    // Route the request to the specific Durable Object for this subdomain
    const id = env.TUNNEL_MANAGER.idFromName(subdomain);
    const stub = env.TUNNEL_MANAGER.get(id);

    return stub.fetch(request);
  }
};