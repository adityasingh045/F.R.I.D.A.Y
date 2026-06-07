const WebSocket = require("ws");

const wss = new WebSocket.Server({
    port: 8080
});

console.log("WebSocket Server Running");

let clients = [];

wss.on("connection", (ws) => {
    console.log("New Device Connected");

    ws.send("Connected to server");

    ws.on("message", (message) => {
        console.log("Message:", message.toString());

        ws.send("Server received: " + message);
    });


    ws.on("close", () => {

        clients = clients.filter(c => c !== ws);

        console.log("Client Disconnected");
    });
});