import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {

    return MaterialApp(
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});


  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  late WebSocketChannel channel;

  String message = "Waiting...";

  @override
  void initState() {

    super.initState();

    channel = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:8080'),
    );

    channel.stream.listen((data) {

      setState(() {
        message = data.toString();
      });
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("SpatialOS Desktop"),
      ),

      body: Center(
        child: Text(message),
      ),

      floatingActionButton: FloatingActionButton(

        onPressed: () {

          channel.sink.add("Hello from Desktop");
        },

        child: const Icon(Icons.send),
      ),
    );
  }
}