const WebSocket = require("ws");

const wss = new WebSocket.Server({
    port: 8080
});

console.log("WebSocket Server Running");

let clients = [];

wss.on("connection", (ws) => {

    console.log("New Device Connected");

    clients.push(ws);

    ws.on("message", (message) => {

        console.log("Message:", message.toString());

        // Broadcast to all clients
        clients.forEach(client => {

            if (
                client !== ws &&
                client.readyState === WebSocket.OPEN
            ) {
                client.send(message);
            }
        });
    });

    ws.on("close", () => {

        clients = clients.filter(c => c !== ws);

        console.log("Client Disconnected");
    });
});