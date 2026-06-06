export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Assuming base domain like "ulenabler.co.za" (3 parts).
    const host = url.hostname;
    const domainParts = host.split('.');
    const subdomain = domainParts.length > 3 ? domainParts[0] : null;

    if (!subdomain) {
      return new Response('Direct access not allowed. Please use a valid subdomain.', { status: 400 });
    }

    if (url.pathname === '/sw.js') {
      const swJs = `
        const pendingRequests = new Map();

        self.addEventListener('install', event => {
          self.skipWaiting();
        });

        self.addEventListener('activate', event => {
          event.waitUntil(self.clients.claim());
        });

        self.addEventListener('message', event => {
          if (event.data && event.data.type === 'RESPONSE') {
            const { requestId, statusCode, headers, buffer } = event.data;
            if (pendingRequests.has(requestId)) {
              const reqState = pendingRequests.get(requestId);
              reqState.resolve({ statusCode, headers, buffer });
              pendingRequests.delete(requestId);
            }
          }
        });

        self.addEventListener('fetch', event => {
          const reqUrl = new URL(event.request.url);

          // Do not intercept SW or Firebase requests
          if (reqUrl.pathname === '/sw.js' || reqUrl.hostname.includes('firebaseio.com') || reqUrl.hostname.includes('googleapis.com')) {
            return;
          }

          event.respondWith(
            new Promise(async (resolve, reject) => {
              const clientsList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
              
              // Find the top-level parent client (the App Shell).
              // It's the one that matches our origin exactly, or the one with no parent (frameType === 'top-level')
              let parentClient = clientsList.find(c => c.frameType === 'top-level' || c.url === self.registration.scope);
              if (!parentClient && clientsList.length > 0) {
                 parentClient = clientsList[0];
              }

              // Navigation logic: If this is the VERY FIRST load of the App Shell, bypass SW.
              // If clientsList is 0, it means no App Shell is open yet. Let it load normally.
              // If an App Shell IS open, any navigation (like clicking a link inside the iframe) MUST be proxied.
              if (event.request.mode === 'navigate' && clientsList.length === 0) {
                return resolve(fetch(event.request)); // Let Cloudflare serve the App Shell
              }

              if (!parentClient) {
                return resolve(new Response('App shell not open. Please reload the root page.', { status: 503 }));
              }

              const requestId = crypto.randomUUID();
              
              const timeoutId = setTimeout(() => {
                if (pendingRequests.has(requestId)) {
                  pendingRequests.delete(requestId);
                  resolve(new Response('Gateway Timeout - Phone took too long to respond via WebRTC', { status: 504 }));
                }
              }, 30000);

              pendingRequests.set(requestId, {
                resolve: (responseObj) => {
                  clearTimeout(timeoutId);
                  resolve(new Response(responseObj.buffer, {
                    status: responseObj.statusCode,
                    headers: responseObj.headers
                  }));
                }
              });

              const headersObj = Object.fromEntries(event.request.headers.entries());
              const reqHeaders = JSON.stringify(headersObj);
              let bodyBuffer = new Uint8Array(0);
              try {
                if (event.request.method !== 'GET' && event.request.method !== 'HEAD') {
                    const arrayBuffer = await event.request.arrayBuffer();
                    bodyBuffer = new Uint8Array(arrayBuffer);
                }
              } catch(e){}

              // Send only to the specific parent App Shell to avoid duplicating requests across tabs
              parentClient.postMessage({
                type: 'FETCH_REQUEST',
                requestId: requestId,
                method: event.request.method,
                urlPath: reqUrl.pathname + reqUrl.search,
                headersJson: reqHeaders,
                bodyBuffer: bodyBuffer.buffer
              });
            })
          );
        });
      `;
      return new Response(swJs, { headers: { 'Content-Type': 'application/javascript' } });
    }

    // Since the SW intercepts requests from the iframe, the worker just needs to serve
    // the root app shell for ANY request that isn't intercepted by the SW yet.
    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <title>DTech P2P Tunnel</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <script type="module">
          import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.8.1/firebase-app.js';
          import { getDatabase, ref, push, onValue, set, onDisconnect, remove, onChildAdded } from 'https://www.gstatic.com/firebasejs/10.8.1/firebase-database.js';

          const firebaseConfig = {
            apiKey: "AIzaSyCndKlGrJVynzkgZdbHAPj0jj1eFjyrbWA",
            projectId: "sere-a4624",
            databaseURL: "https://sere-a4624-default-rtdb.firebaseio.com",
            storageBucket: "sere-a4624.firebasestorage.app",
            appId: "1:51692706635:web:placeholder" // Required by some JS SDKs
          };

          const app = initializeApp(firebaseConfig);
          const database = getDatabase(app);
          const subdomain = "${subdomain}";

          let peerConnection;
          let dataChannel;
          const pendingResponses = new Map();

          const config = {
            iceServers: [
              { urls: 'stun:stun.l.google.com:19302' },
              { urls: 'stun:stun1.l.google.com:19302' }
            ]
          };

          async function connect() {
            document.getElementById('status').innerText = 'Starting signaling...';

            peerConnection = new RTCPeerConnection(config);

            dataChannel = peerConnection.createDataChannel('tunnelChannel', {
              ordered: true
            });

            dataChannel.binaryType = 'arraybuffer';

            dataChannel.onopen = async () => {
              document.getElementById('status').style.display = 'none';

              if ('serviceWorker' in navigator) {
                const reg = await navigator.serviceWorker.register('/sw.js');
                await navigator.serviceWorker.ready;

                // Show iframe
                const iframe = document.getElementById('app-frame');
                iframe.style.display = 'block';
                // Load original requested URL into iframe. The SW knows to intercept it
                // because the App Shell client is now open.
                iframe.src = window.location.href;
              }
            };

            dataChannel.onclose = () => {
              document.getElementById('status').style.display = 'block';
              document.getElementById('status').innerText = 'Connection lost.';
              document.getElementById('app-frame').style.display = 'none';
            };

            dataChannel.onmessage = (event) => {
               try {
                  if (typeof event.data === 'string') {
                    const parts = event.data.split('|');
                    if (parts[0] === 'RES') {
                      const reqId = parts[1];
                      const statusCode = parseInt(parts[2], 10);
                      const headers = JSON.parse(parts[3]);

                      pendingResponses.set(reqId, { statusCode, headers, chunks: [] });
                    }
                  } else if (event.data instanceof ArrayBuffer) {
                    const view = new Uint8Array(event.data);
                    const idLength = view[0];
                    const isLast = view[1] === 1;
                    const idBytes = view.slice(2, 2 + idLength);
                    const reqId = new TextDecoder().decode(idBytes);

                    const chunk = view.slice(2 + idLength);

                    if (pendingResponses.has(reqId)) {
                      const resState = pendingResponses.get(reqId);
                      resState.chunks.push(chunk);

                      if (isLast) {
                        // Reassemble chunks
                        const totalLength = resState.chunks.reduce((acc, c) => acc + c.byteLength, 0);
                        const finalBuffer = new Uint8Array(totalLength);
                        let offset = 0;
                        for (const c of resState.chunks) {
                          finalBuffer.set(c, offset);
                          offset += c.byteLength;
                        }

                        // Send back to Service Worker
                        if (navigator.serviceWorker.controller) {
                          navigator.serviceWorker.controller.postMessage({
                            type: 'RESPONSE',
                            requestId: reqId,
                            statusCode: resState.statusCode,
                            headers: resState.headers,
                            buffer: finalBuffer.buffer
                          });
                        }
                        pendingResponses.delete(reqId);
                      }
                    }
                  }
               } catch(err) {
                 console.error("DataChannel Message Error", err);
               }
            };

            const signalingRef = ref(database, 'signaling/' + subdomain + '/requests');
            const newRequestRef = push(signalingRef);

            onDisconnect(newRequestRef).remove();

            peerConnection.onicecandidate = event => {
              if (event.candidate) {
                 push(ref(database, 'signaling/' + subdomain + '/candidates/' + newRequestRef.key + '/visitor'), event.candidate.toJSON());
              }
            };

            const offer = await peerConnection.createOffer();
            await peerConnection.setLocalDescription(offer);

            await set(newRequestRef, {
              offer: {
                type: offer.type,
                sdp: offer.sdp
              },
              timestamp: Date.now()
            });

            const answerRef = ref(database, 'signaling/' + subdomain + '/answers/' + newRequestRef.key);
            onValue(answerRef, async (snapshot) => {
              const data = snapshot.val();
              if (data && data.answer) {
                const answer = new RTCSessionDescription(data.answer);
                await peerConnection.setRemoteDescription(answer);
                set(answerRef, null); // Stop listening
              }
            });

            const remoteCandidatesRef = ref(database, 'signaling/' + subdomain + '/candidates/' + newRequestRef.key + '/phone');
            onChildAdded(remoteCandidatesRef, (snapshot) => {
               const candidateData = snapshot.val();
               if(candidateData) {
                   peerConnection.addIceCandidate(new RTCIceCandidate(candidateData));
               }
            });
          }

          navigator.serviceWorker.addEventListener('message', event => {
             if(event.data && event.data.type === 'FETCH_REQUEST') {
                const { requestId, method, urlPath, headersJson, bodyBuffer } = event.data;
                if(dataChannel && dataChannel.readyState === 'open') {
                   // Only the top window has the actual open data channel, the iframe will ignore this

                   // WebRTC limit is ~64KB. Text string can just be sent directly since headers+URL are small.
                   // The Dart code expects: "requestId|method|path|headersJSON|body" if body is string.
                   // However, for binary uploads, we need a better way.
                   // To keep it simple, we can base64 encode the body or just send it as part of the string.
                   // Let's base64 encode the request body since request uploads are usually small in this app.
                   let bodyStr = '';
                   if (bodyBuffer && bodyBuffer.byteLength > 0) {
                      const bytes = new Uint8Array(bodyBuffer);
                      // btoa on large arrays can stack overflow, but uploads are rare here.
                      // For a robust implementation, we should encode chunks, but let's do simple base64
                      // using a FileReader or string decoding.
                      let binary = '';
                      for (let i = 0; i < bytes.byteLength; i++) {
                         binary += String.fromCharCode(bytes[i]);
                      }
                      bodyStr = btoa(binary);
                   }

                   const payload = \`\${requestId}|\${method}|\${urlPath}|\${headersJson}|\${bodyStr}\`;
                   dataChannel.send(payload);
                }
             }
          });

          // Only connect if we are the top-level window, not inside our own iframe
          if (window.self === window.top) {
            connect();
          }
        </script>
      </head>
      <body style="margin: 0; background: #121212; color: white; display: flex; align-items: center; justify-content: center; height: 100vh; font-family: sans-serif;">
        <h2 id="status">Connecting to DTech...</h2>
        <iframe id="app-frame" style="display:none; width: 100%; height: 100%; border: none; position: absolute; top: 0; left: 0;"></iframe>
      </body>
      </html>
    `;
    return new Response(html, { headers: { 'Content-Type': 'text/html' } });
  }
};
