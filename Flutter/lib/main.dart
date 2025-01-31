import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FtpFileExplorer(),
    );
  }
}

class FtpFileExplorer extends StatefulWidget {
  @override
  _FtpFileExplorerState createState() => _FtpFileExplorerState();
}

class _FtpFileExplorerState extends State<FtpFileExplorer> {
  List<Map<String, dynamic>> items = [];
  String currentPath = "";

  Future<void> fetchFiles([String path = ""]) async {
    setState(() {
      currentPath = path;
      items = []; // Clear previous list
    });

    try {
      final response =
          await http.get(Uri.parse("http://localhost:8000/list-files/$path"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          items = (data['items'] as List?)?.map((item) => item as Map<String, dynamic>).toList() ?? [];
        });
      } else {
        throw Exception("Failed to load files");
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<void> downloadFile(String filename) async {
    final url = "http://localhost:8000/download/$currentPath/$filename";
    print("Downloading from: $url");
    // Add file download logic, for example using `flutter_downloader` to save files to device storage
  }

  @override
  void initState() {
    super.initState();
    fetchFiles(); // Load root directory
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(currentPath.isEmpty ? "FTP Explorer" : "FTP: /$currentPath"),
        leading: currentPath.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () {
                  var parts = currentPath.split('/');
                  parts.removeLast();
                  fetchFiles(parts.join('/'));
                },
              )
            : null,
      ),
      body: items.isEmpty
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Icon(
                      item['is_dir'] ? Icons.folder : Icons.insert_drive_file),
                  title: Text(item['name']),
                  trailing: !item['is_dir']
                      ? IconButton(
                          icon: Icon(Icons.download),
                          onPressed: () => downloadFile(item['name']),
                        )
                      : null,
                  onTap: () {
                    if (item['is_dir']) {
                      fetchFiles("$currentPath/${item['name']}");
                    }
                  },
                );
              },
            ),
    );
  }
}
