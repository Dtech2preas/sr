// worker.js - Cloudflare Worker for DTech WebSockets (Free Tier)

// In-memory Map to store WebSocket connections.
// This works perfectly for testing where your phone and laptop hit the same Cloudflare node.
const activeTunnels = new Map();

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1. App Registration Route (Phone connecting)
    if (url.pathname === '/register') {
      const upgradeHeader = request.headers.get('Upgrade');
      if (!upgradeHeader || upgradeHeader !== 'websocket') {
        return new Response('Expected Upgrade: websocket', { status: 426 });
      }

      const subdomain = url.searchParams.get('subdomain');
      const token = url.searchParams.get('token');
      
      if (!subdomain) {
        return new Response('Missing subdomain parameter', { status: 400 });
      }

      const webSocketPair = new WebSocketPair();
      const [client, server] = Object.values(webSocketPair);

      server.accept();

      // Create a pending requests map for this specific connection
      const pendingRequests = new Map();

      // Store both the socket and the pending requests map
      activeTunnels.set(subdomain, { socket: server, pendingRequests });

      server.addEventListener('close', () => {
        if (activeTunnels.has(subdomain) && activeTunnels.get(subdomain).socket === server) {
          activeTunnels.delete(subdomain);
        }
      });
      
      server.addEventListener('error', () => {
        if (activeTunnels.has(subdomain) && activeTunnels.get(subdomain).socket === server) {
          activeTunnels.delete(subdomain);
        }
      });

      // Handle responses coming back from the phone
      server.addEventListener('message', (event) => {
        try {
          if (typeof event.data === 'string') {
            const parts = event.data.split('|');
            if (parts[0] === 'RES') {
              const reqId = parts[1];
              const statusCode = parseInt(parts[2], 10);
              const headers = JSON.parse(parts[3]);
              
              if (pendingRequests.has(reqId)) {
                const reqState = pendingRequests.get(reqId);
                reqState.statusCode = statusCode;
                reqState.headers = headers;
              }
            }
          } else if (event.data instanceof ArrayBuffer) {
            const view = new Uint8Array(event.data);
            const idLength = view[0];
            const idBytes = view.slice(1, 1 + idLength);
            const reqId = new TextDecoder().decode(idBytes);
            
            if (pendingRequests.has(reqId)) {
              const reqState = pendingRequests.get(reqId);
              const bodyBytes = view.slice(1 + idLength);
              
              // Resolve the original promise waiting for the response
              reqState.resolve({
                body: bodyBytes.length > 0 ? bodyBytes : null,
                statusCode: reqState.statusCode || 200,
                headers: reqState.headers || {}
              });
              
              pendingRequests.delete(reqId);
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
    const host = url.hostname;
    const domainParts = host.split('.');
    const subdomain = domainParts.length > 2 ? domainParts[0] : null;

    if (!subdomain) {
      return new Response('Direct access not allowed. Please use a valid subdomain.', { status: 400 });
    }

    const tunnel = activeTunnels.get(subdomain);

    if (!tunnel) {
      return new Response(`No active tunnel found for subdomain: ${subdomain}. Server might be offline.`, { status: 404 });
    }

    return new Promise((resolve) => {
      const requestId = crypto.randomUUID();
      
      // Setup the promise to resolve when the phone answers
      tunnel.pendingRequests.set(requestId, {
        resolve: (responseObj) => {
          clearTimeout(timeoutId);
          resolve(new Response(responseObj.body, {
            status: responseObj.statusCode,
            headers: responseObj.headers
          }));
        }
      });

      // 30-second timeout
      const timeoutId = setTimeout(() => {
        if (tunnel.pendingRequests.has(requestId)) {
          tunnel.pendingRequests.delete(requestId);
          resolve(new Response('Gateway Timeout - Phone took too long to respond', { status: 504 }));
        }
      }, 30000);

      // Send request to phone
      const headersObj = Object.fromEntries(request.headers.entries());
      const reqHeaders = JSON.stringify(headersObj);
      
      request.text().then(bodyText => {
        const payload = `${requestId}|${request.method}|${url.pathname}${url.search}|${reqHeaders}|${bodyText || ''}`;
        try {
          tunnel.socket.send(payload);
        } catch (e) {
          clearTimeout(timeoutId);
          tunnel.pendingRequests.delete(requestId);
          resolve(new Response('Connection lost', { status: 502 }));
        }
      }).catch(e => {
        clearTimeout(timeoutId);
        tunnel.pendingRequests.delete(requestId);
        resolve(new Response('Error reading request body', { status: 500 }));
      });
    });
  }
};
