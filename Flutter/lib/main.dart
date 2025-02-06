import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Sync App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  TextEditingController _emailController = TextEditingController();
  String? requestToken;
  bool isOtpPage = false;
  bool noEmail = false;

  void _getRequestToken(String email) async {
    final response = await http.get(Uri.parse('https://filelu.com/api/session/request?email=$email'));

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      if (data.containsKey('request_token')) {
        setState(() {
          requestToken = data['request_token'];
          isOtpPage = true;
        });
      } else {
        print(data['msg']);
        setState(() {
          noEmail = true;
        });
      }
    } else {
      print('Failed to get request token');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isOtpPage)
              Column(
                children: [
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(labelText: 'Email'),
                  ),
                  if (noEmail)
                    Text("No Email"),
                  ElevatedButton(
                    onPressed: () {
                      if (_emailController.text.isNotEmpty) {
                        _getRequestToken(_emailController.text);
                      } else {
                        print('Email cannot be empty');
                      }
                    },
                    child: Text('Get OTP'),
                  ),
                ],
              ),
            if (isOtpPage && requestToken != null)
              OtpPage(requestToken: requestToken!), // Pass non-null requestToken here
            if (isOtpPage && requestToken == null)
              Center(child: CircularProgressIndicator()), // Show loading until requestToken is available
          ],
        ),
      ),
    );
  }
}

class OtpPage extends StatefulWidget {
  final String requestToken;
  OtpPage({required this.requestToken});

  @override
  _OtpPageState createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  TextEditingController _otpController = TextEditingController();

  void _startSession(String otp) async {
    // Ensure requestToken is not null before making the API call
    if (widget.requestToken.isNotEmpty && otp.isNotEmpty) {
      final response = await http.get(Uri.parse(
          'https://filelu.com/api/session/start?request_token=${widget.requestToken}&otp=$otp'));

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        String sessionId = "";
        if (data.containsKey('sess_id')) {
          sessionId = data['sess_id'];
        } else {
          print("Failed to get session id");
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MyFilesPage(sessionId: sessionId)),
        );
      } else {
        print('Failed to start session');
      }
    } else {
      print('Invalid request token or OTP');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _otpController,
          decoration: InputDecoration(labelText: 'Enter OTP'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_otpController.text.isNotEmpty) {
              _startSession(_otpController.text);
            } else {
              print('OTP cannot be empty');
            }
          },
          child: Text('Submit OTP'),
        ),
      ],
    );
  }
}

class MyFilesPage extends StatefulWidget {
  final String sessionId;
  MyFilesPage({required this.sessionId});

  @override
  _MyFilesPageState createState() => _MyFilesPageState();
}

class _MyFilesPageState extends State<MyFilesPage> {
  List<dynamic> folders = [];
  List<dynamic> files = [];

  @override
  void initState() {
    super.initState();
    _fetchFilesAndFolders();
  }

  // Fetch files and folders using the API
  Future<void> _fetchFilesAndFolders() async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=0&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      setState(() {
        folders = data['result']['folders'];
        files = data['result']['files'];
      });
    } else {
      print('Failed to load folders and files');
    }
  }

  // Handle file/folder options (e.g., rename, download)
  void _showFileOptions(BuildContext context, dynamic item) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          children: [
            ListTile(
              title: Text('Rename'),
              onTap: () {
                // Implement rename logic here
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('Download'),
              onTap: () {
                // Implement download logic here
                Navigator.pop(context);
                _downloadFile(item['link']);
              },
            ),
            ListTile(
              title: Text('Remove'),
              onTap: () {
                // Implement remove logic here
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('Move To'),
              onTap: () {
                // Implement move functionality here
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('Copy'),
              onTap: () {
                // Implement copy functionality here
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  // Example function to download the file
  void _downloadFile(String link) {
    // Implement the logic to download the file (can use packages like `url_launcher` or `dio`)
    print('Downloading file from $link');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('My Files')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // Display Folders
            if (folders.isNotEmpty)
              ...folders.map((folder) {
                return ListTile(
                  leading: Icon(Icons.folder),
                  title: Text(folder['name']),
                  trailing: IconButton(
                    icon: Icon(Icons.more_vert),
                    onPressed: () => _showFileOptions(context, folder),
                  ),
                );
              }).toList(),
            
            // Display Files
            if (files.isNotEmpty)
              ...files.map((file) {
                return ListTile(
                  leading: Image.network(file['thumbnail']),
                  title: Text(file['name']),
                  trailing: IconButton(
                    icon: Icon(Icons.more_vert),
                    onPressed: () => _showFileOptions(context, file),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}

class FileFolder {
  final String name;
  final String id; // You can add more fields if necessary

  FileFolder({required this.name, required this.id});

  factory FileFolder.fromJson(Map<String, dynamic> json) {
    return FileFolder(
      name: json['name'],
      id: json['id'],
    );
  }
}
