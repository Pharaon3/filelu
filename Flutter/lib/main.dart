import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // home: LoginPage(),
      home: MyFilesPage(sessionId: "6f9e1a5eea407bb4d98f841e1a5d7dc1"),
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
  int _selectedIndex = 0; // For bottom navigation index

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

  Future<String> _getDownloadLink(fileCode) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/file/direct_link?file_code=${fileCode}&sess_id=${widget.sessionId}')
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      Uri.parse(data['result']['url']);
      return data['result']['url'];
    } else {
      return "cannot get download link";
    }
  }

  // Handle navigation between pages
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Display different pages based on navigation selection
  Widget _getPageContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildFileFolderList();
      case 1:
        return _buildSyncPage();
      case 2:
        return Center(child: Text("Upload Page"));
      default:
        return _buildFileFolderList();
    }
  }

  // Display file/folder list with options
  Widget _buildFileFolderList() {
    return ListView(
      children: [
        // Display Folders
        if (folders.isNotEmpty)
          ...folders.map((folder) {
            return FileFolder(
              name: folder['name'],
              isFile: false,
              thumbnail: Icon(Icons.folder, size: 40), // Default icon
              onOptionsTap: () => _showOptions(context, folder),
            );
          }).toList(),

        // Display Files
        if (files.isNotEmpty)
          ...files.map((file) {
            return FileFolder(
              name: file['name'],
              isFile: true,
              thumbnail: Image.network(file['thumbnail']),
              onOptionsTap: () => _showOptions(context, file),
            );
          }).toList(),
      ],
    );
  }

  // Display file/folder list with options
  Widget _buildSyncPage() {
    return SyncPage(sessionId: widget.sessionId,);
  }

  // Show options (Rename, Copy, Move To, Download, Remove) for file/folder
  void _showOptions(BuildContext context, dynamic item) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return FileOptions(
          item: item,
          onRename: () {
            Navigator.pop(context);
            // Implement Rename Logic here
            print('Rename ${item['name']}');
          },
          onCopy: () {
            Navigator.pop(context);
            // Implement Copy Logic here
            print('Copy ${item['name']}');
          },
          onMove: () {
            Navigator.pop(context);
            // Implement Move Logic here
            print('Move ${item['name']}');
          },
          onDownload: () {
            Navigator.pop(context);
            _downloadFile(item['file_code']);
          },
          onRemove: () {
            Navigator.pop(context);
            // Implement Remove Logic here
            print('Remove ${item['name']}');
          },
        );
      },
    );
  }

  // Example function to download the file
  void _downloadFile(String link) {
    // Implement the logic to download the file (can use packages like `url_launcher` or `dio`)
    String donwloadLink = _getDownloadLink(link).toString();
    print('Downloading file from $donwloadLink');

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('My Files')),
      body: _getPageContent(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.folder),
            label: 'My Files',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sync),
            label: 'Sync',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.upload),
            label: 'Upload',
          ),
        ],
      ),
    );
  }
}

// A widget for displaying files or folders in the list
class FileFolder extends StatelessWidget {
  final String name;
  final bool isFile;
  final Widget thumbnail;
  final VoidCallback onOptionsTap;

  const FileFolder({
    required this.name,
    required this.isFile,
    required this.thumbnail,
    required this.onOptionsTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: thumbnail,
      title: Text(name),
      trailing: IconButton(
        icon: Icon(Icons.more_vert),
        onPressed: onOptionsTap,
      ),
    );
  }
}

// A widget for showing file/folder options
class FileOptions extends StatelessWidget {
  final dynamic item;
  final VoidCallback onRename;
  final VoidCallback onCopy;
  final VoidCallback onMove;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  const FileOptions({
    required this.item,
    required this.onRename,
    required this.onCopy,
    required this.onMove,
    required this.onDownload,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          title: Text('Rename'),
          onTap: onRename,
        ),
        ListTile(
          title: Text('Copy'),
          onTap: onCopy,
        ),
        ListTile(
          title: Text('Move To'),
          onTap: onMove,
        ),
        ListTile(
          title: Text('Download'),
          onTap: onDownload,
        ),
        ListTile(
          title: Text('Remove'),
          onTap: onRemove,
        ),
      ],
    );
  }
}

class SyncPage extends StatefulWidget {
  final String sessionId;
  SyncPage({required this.sessionId});

  @override
  _SyncPageState createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  List<String> cloudFiles = [];
  List<String> localFiles = [];
  List<String> cloudFolders = [];
  List<String> localFolders = [];
  List<String> missingOnCloud = [];
  List<String> missingLocally = [];
  List<String> missingFoldersOnCloud = [];
  List<String> missingFoldersLocally = [];

  @override
  void initState() {
    super.initState();
    _compareRepositories();
  }

  Future<void> _fetchCloudData() async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=0&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      setState(() {
        cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
        cloudFolders = List<String>.from(data['result']['folders'].map((folder) => folder['name']));
      });
    } else {
      print('Failed to load cloud data');
    }
  }

  void _fetchLocalData() {
    String localPath;
    if (Platform.isWindows) {
      localPath = "C:\\Users\\1\\Documents\\MySyncFolder";
    } else {
      localPath = "/storage/emulated/0/MySyncFolder";
    }

    Directory dir = Directory(localPath);
    if (dir.existsSync()) {
      setState(() {
        localFiles = dir
            .listSync()
            .where((e) => e is File)
            .map((e) => e.path.split(Platform.pathSeparator).last)
            .toList();
        localFolders = dir
            .listSync()
            .where((e) => e is Directory)
            .map((e) => e.path.split(Platform.pathSeparator).last)
            .toList();
      });
    } else {
      print("Local folder does not exist");
    }
  }

  void _compareRepositories() async {
    await _fetchCloudData();
    _fetchLocalData();
    setState(() {
      missingOnCloud = localFiles.where((file) => !cloudFiles.contains(file)).toList();
      missingLocally = cloudFiles.where((file) => !localFiles.contains(file)).toList();
      missingFoldersOnCloud = localFolders.where((folder) => !cloudFolders.contains(folder)).toList();
      missingFoldersLocally = cloudFolders.where((folder) => !localFolders.contains(folder)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sync Files & Folders')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                ListTile(title: Text("Missing Files on Cloud"), subtitle: Text(missingOnCloud.join(", "))),
                ListTile(title: Text("Missing Files Locally"), subtitle: Text(missingLocally.join(", "))),
                ListTile(title: Text("Missing Folders on Cloud"), subtitle: Text(missingFoldersOnCloud.join(", "))),
                ListTile(title: Text("Missing Folders Locally"), subtitle: Text(missingFoldersLocally.join(", "))),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _compareRepositories,
            child: Text("Refresh Comparison"),
          ),
        ],
      ),
    );
  }
}
