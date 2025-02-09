import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  List<dynamic> visitedFolderIDs = [[0, '/'], [0, '/']];

  @override
  void initState() {
    super.initState();
    _fetchFilesAndFolders(0);
  }

  // Fetch files and folders using the API
  Future<void> _fetchFilesAndFolders(fld_id) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$fld_id&sess_id=${widget.sessionId}'),
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
      Uri.parse('https://filelu.com/api/file/direct_link?file_code=$fileCode&sess_id=${widget.sessionId}')
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      Uri.parse(data['result']['url']);
      return data['result']['url'];
    } else {
      return "cannot get download link";
    }
  }

  Future<String> getDownloadDirectory() async {
    String subpath = visitedFolderIDs.map((entry) => entry[1]).join('/');
    if (Platform.isAndroid) {
      return "/storage/emulated/0/Download"; // Default download folder on Android
    } else if (Platform.isIOS) {
      Directory dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } else if (Platform.isWindows) {
      String? userHome = Platform.environment['USERPROFILE']; // Get user home directory
      return "$userHome\\Documents\\MySyncFolder\\$subpath"; // Default downloads folder in Windows
    } else if (Platform.isMacOS) {
      Directory dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      return dir.path;
    } else if (Platform.isLinux) {
      String? home = Platform.environment['HOME'];
      return "$home/Downloads"; // Default downloads folder in Linux
    } else {
      throw Exception("Unsupported platform");
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
    return Scaffold(
      appBar: AppBar(
        title: Text('My Files'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            _backCloudFolder();
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.home),
            onPressed: () {
              _homeCloudFolder();
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          if (folders.isNotEmpty || files.isNotEmpty) ...[
            // Display Folders
            if (folders.isNotEmpty)
              ...folders.map((folder) {
                return FileFolder(
                  name: folder['name'],
                  isFile: false,
                  thumbnail: Icon(Icons.folder, size: 40), // Default icon
                  onOptionsTap: () => _showOptions(context, folder),
                  onOpenFileFolder: () => _openCloudFolder(context, folder),
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
                  onOpenFileFolder: () => openCloudFile(context, file['file_code'], file['name']),
                );
              }).toList(),
          ] else ...[
            Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "This folder is empty",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
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
            if(item.containsKey('file_code')) {
              downloadFile(item['file_code'], item['name'], "");
            } else {
              downloadFolder(item['fld_id'], item['name']);
            }
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

  // Open Cloud Folder and show Files/Folders in it.
  void _openCloudFolder(BuildContext context, dynamic item) async {
    try {
      await _fetchFilesAndFolders(item["fld_id"]);
      visitedFolderIDs.add([item['fld_id'], item['name']]);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // Show text file content inside a dialog
  Future<void> openCloudFile(BuildContext context, String fileCode, String fileName) async {
    try {
      String downloadLink = await _getDownloadLink(fileCode);
      final response = await http.get(Uri.parse(downloadLink));

      if (response.statusCode == 200) {
        // Get the temporary directory
        Directory tempDir = await getTemporaryDirectory();
        String filePath = '${tempDir.path}/$fileName';

        // Write the file to local storage
        File file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        // Get file extension
        String fileExtension = fileName.split('.').last.toLowerCase();

        // Check file type and open it
        if (['txt'].contains(fileExtension)) {
          _showTextFile(context, file);
        } else if (['png', 'jpg', 'jpeg', 'gif'].contains(fileExtension)) {
          _showImageFile(context, file);
        } else if (['mp3', 'wav', 'aac'].contains(fileExtension)) {
          _playAudioFile(context, file);
        } else if (['mp4', 'avi', 'mov'].contains(fileExtension)) {
          _playVideoFile(context, file);
        } else {
          print("Unsupported file format: $fileExtension");
        }
      } else {
        print("Failed to download file. Status Code: ${response.statusCode}");
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  // Show text file content
  void _showTextFile(BuildContext context, File file) async {
    String content = await file.readAsString();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Text File"),
          content: SingleChildScrollView(
            child: Text(content),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        );
      },
    );
  }

  // Show image file
  void _showImageFile(BuildContext context, File file) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Image File"),
          content: Image.file(file),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        );
      },
    );
  }

  // Play audio file
  void _playAudioFile(BuildContext context, File file) {
    AudioPlayer audioPlayer = AudioPlayer();
    audioPlayer.play(DeviceFileSource(file.path));

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Audio Player"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.audiotrack, size: 50, color: Colors.blue),
              SizedBox(height: 10),
              Text("Playing: ${file.path.split('/').last}"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                audioPlayer.stop();
                Navigator.pop(context);
              },
              child: Text("Stop"),
            ),
          ],
        );
      },
    );
  }

  // Play video file
  void _playVideoFile(BuildContext context, File file) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => VideoPlayerScreen(videoFile: file)),
    );
  }

  void _backCloudFolder() async {
    try {
      visitedFolderIDs.removeLast();
      await _fetchFilesAndFolders(visitedFolderIDs.last.first);
    } catch (e) {
      print(e);
    }
  }

  void _homeCloudFolder() async {
    try {
      visitedFolderIDs = [[0, '/'], [0, '/']];
      await _fetchFilesAndFolders(visitedFolderIDs.last.first);
    } catch (e) {
      print(e);
    }
  }

  Future<void> downloadFile(String fileCode, String fileName, String filePath) async {
    String saveDirectory = filePath;
    if (filePath == "") saveDirectory = await getDownloadDirectory();
    try {
      // Step 1: Get the download link
      String downloadLink = await _getDownloadLink(fileCode);

      // Step 2: Request storage permission (for Android)
      if (Platform.isAndroid) {
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          print("Storage permission denied");
          return;
        }
      }

      // Step 3: Get the file from the server
      final response = await http.get(Uri.parse(downloadLink));

      if (response.statusCode == 200) {
        // Step 4: Get the custom local directory (e.g., Downloads folder)
        Directory directory = Directory(saveDirectory);
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }

        // Step 5: Save the file to the specified path
        String filePath = '${directory.path}/$fileName';
        File file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        print("Download complete! File saved at: $filePath");
      } else {
        print("Download failed. Server response: ${response.statusCode}");
      }
    } catch (e) {
      print("Error downloading file: $e");
    }
  }

  Future<void> downloadFolder(int folderID, String folderName, [String subpath = ""]) async {
    String saveDirectory;
    if (subpath == "") {
      saveDirectory = "${await getDownloadDirectory()}/$folderName";
    } else {
      saveDirectory = "$subpath/$folderName";
    }
    await createFolderIfNotExists(saveDirectory);
    dynamic fileFolders = await fetchFilesAndFolders(folderID);
    if (fileFolders.containsKey('folders')) {
      dynamic folders = fileFolders['folders'];
      for (dynamic folder in folders) {
        downloadFolder(folder['fld_id'], folder['name'], saveDirectory);
      }
    }
    if (fileFolders.containsKey('files')) {
      dynamic files = fileFolders['files'];
      for (dynamic file in files) {
        downloadFile(file['file_code'], file['name'], saveDirectory);
      }
    }
  }

  Future<void> createFolderIfNotExists(String path) async {
    final directory = Directory(path);

    // Check if the directory exists
    if (await directory.exists()) {
      print('Directory already exists: $path');
    } else {
      // Create the directory
      await directory.create(recursive: true);
      print('Directory created: $path');
    }
  }

  // Fetch files and folders using the API
  Future<dynamic> fetchFilesAndFolders(fld_id) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$fld_id&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['result'];
    } else {
      print('Failed to load folders and files');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
  final VoidCallback onOpenFileFolder;

  const FileFolder({
    required this.name,
    required this.isFile,
    required this.thumbnail,
    required this.onOptionsTap,
    required this.onOpenFileFolder,
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
      onTap: onOpenFileFolder,
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
  _SyncPageState createState() => _SyncPageState(sessionId: sessionId);
}

class SyncOrder {
  String localPath;
  String syncType; // Upload Only, Download Only, etc.
  bool isRunning;
  String remotePath;

  SyncOrder({
    required this.localPath,
    required this.syncType,
    this.isRunning = false,
    required this.remotePath,
  });

  // Convert SyncOrder to JSON
  Map<String, dynamic> toJson() {
    return {
      'localPath': localPath,
      'syncType': syncType,
      'isRunning': isRunning,
      'remotePath': remotePath,
    };
  }

  // Create SyncOrder from JSON
  factory SyncOrder.fromJson(Map<String, dynamic> json) {
    return SyncOrder(
      localPath: json['localPath'],
      syncType: json['syncType'],
      isRunning: json['isRunning'] ?? false,
      remotePath: json['remotePath'],
    );
  }
}

class _SyncPageState extends State<SyncPage> {
  List<SyncOrder> syncOrders = [];
  List<List<String>> syncedFiles = [];
  String uploadServer = "";
  final String sessionId;

  _SyncPageState({required this.sessionId});

  @override
  void initState() {
    super.initState();
    _loadSyncOrders(); 
    _initializeServerUrl();
  }

  Future<void> _initializeServerUrl() async {
    try {
      final response = await http.get(
        Uri.parse('https://filelu.com/api/upload/server?sess_id=$sessionId'),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        uploadServer = data['result'];
        print("Upload server initialized: $uploadServer");
      } else {
        print("Failed to get upload server: ${response.reasonPhrase}");
      }
    } catch (e) {
      print("Error fetching upload server: $e");
    }
  }

  /// Load sync orders from local storage
  Future<void> _loadSyncOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedOrders = prefs.getString('sync_orders');
    final String? storedSyncedFiles = prefs.getString('stored_files');

    if (storedOrders != null) {
      setState(() {
        List<dynamic> decoded = jsonDecode(storedOrders);
        syncOrders = decoded.map((e) => SyncOrder.fromJson(e)).toList();
      });
    }

    if (storedSyncedFiles != null) {
      setState(() {
        List<dynamic> decoded = jsonDecode(storedSyncedFiles);
        syncedFiles = decoded.map((e) => List<String>.from(e)).toList();
        print(syncedFiles);
      });
    }
  }

  /// Save sync orders to local storage
  Future<void> _saveSyncOrders() async {
    final prefs = await SharedPreferences.getInstance();
    String encodedOrders = jsonEncode(syncOrders.map((e) => e.toJson()).toList());
    await prefs.setString('sync_orders', encodedOrders);
  }

  Future<void> _saveSyncFiles() async {
    final prefs = await SharedPreferences.getInstance();
    String encodedOrders = jsonEncode(syncedFiles);
    await prefs.setString('stored_files', encodedOrders);
  }

  /// Add new Sync Order
  void _addSyncOrder(String localPath, String syncType, String remotePath) {
    setState(() {
      syncOrders.add(SyncOrder(localPath: localPath, syncType: syncType, remotePath: remotePath));
    });
    _saveSyncOrders();
  }

  /// Delete Sync Order
  void _deleteSyncOrder(int index) {
    setState(() {
      syncOrders.removeAt(index);
    });
    _saveSyncOrders();
  }

  /// Start/Stop Sync Order
  void _toggleSync(int index) async {
    setState(() {
      syncOrders[index].isRunning = !syncOrders[index].isRunning;
    });
    _saveSyncOrders();
    while (syncOrders[index].isRunning) {
      await _performSync(syncOrders[index]);
      await Future.delayed(Duration(seconds: 10)); // Run every 10 seconds
    }
  }

  /// Show Add Sync Order Popup
  void _showAddSyncOrderDialog() {
    String selectedType = "Upload Only";
    TextEditingController folderController = TextEditingController();
    String remotePath = "";

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Add Sync Order"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Folder path input
              TextField(
                controller: folderController,
                decoration: InputDecoration(
                  labelText: "Local Folder Path",
                  suffixIcon: IconButton(
                    icon: Icon(Icons.folder),
                    onPressed: () async {
                      String? selectedFolder = await _pickFolder();
                      if (selectedFolder != null) {
                        folderController.text = selectedFolder;
                      }
                    },
                  ),
                ),
                readOnly: true,
              ),
              SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(labelText: "Remote Folder"),
                onChanged: (value) => remotePath = value,
              ),
              SizedBox(height: 10),
              // Sync type dropdown
              DropdownButton<String>(
                value: selectedType,
                onChanged: (value) {
                  setState(() => selectedType = value!);
                },
                items: [
                  "Upload Only",
                  "Download Only",
                  "One-Way Sync",
                  "Two-Way Sync"
                ].map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _addSyncOrder(folderController.text, selectedType, remotePath);
                Navigator.pop(context);
              },
              child: Text("Add"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel"),
            ),
          ],
        );
      },
    );
  }
  
  Future<String?> _pickFolder() async {
    String? selectedFolder;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      selectedFolder = await FilePicker.platform.getDirectoryPath();
    } else if (Platform.isAndroid || Platform.isIOS) {
      selectedFolder = await FilePicker.platform.getDirectoryPath();
    }
    return selectedFolder;
  }

  Future<void> _performSync(SyncOrder order) async {
    List<String> cloudFiles = [];
    List<String> cloudFolders = [];
    List<String> cloudFileCodes = [];
    List<String> cloudFolderCodes = [];
    List<String> localFiles = [];

    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=0&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
      cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code']));
      cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
      cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id']));
    }

    Directory dir = Directory(order.localPath);
    if (dir.existsSync()) {
      localFiles = dir.listSync().whereType<File>().map((e) => e.path.split(Platform.pathSeparator).last).toList();
    }

    switch (order.syncType) {
      case "Upload Only":
        await _uploadFiles(localFiles, cloudFiles, order.localPath);
        break;
      case "Download Only":
        await _downloadFiles(localFiles, cloudFiles, cloudFileCodes, order.localPath);
        break;
      case "One-Way Sync":
        await _uploadFiles(localFiles, cloudFiles, order.localPath);
        await _deleteCloudExtras(localFiles, cloudFiles, cloudFileCodes);
        break;
      case "Two-Way Sync":
        await _uploadFiles(localFiles, syncedFiles[0], order.localPath);
        await _downloadFiles(syncedFiles[0], cloudFiles, cloudFileCodes, order.localPath);
        await _deleteCloudExtras(localFiles, syncedFiles[0], syncedFiles[1]);
        await _deleteLocalExtras(syncedFiles[0], cloudFiles, order.localPath);
        break;
    }

    // Update synced files.
    final response1 = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=0&sess_id=${widget.sessionId}'),
    );

    if (response1.statusCode == 200) {
      var data = jsonDecode(response1.body);
      cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
      cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code']));
      setState(() {
        syncedFiles = [cloudFiles, cloudFileCodes];
        print(syncedFiles);
      });
    }

    _saveSyncFiles();
  }

  Future<void> _uploadFiles(List<String> localFiles, List<String> cloudFiles, String localPath) async {
    for (String file in localFiles) {
      if (!cloudFiles.contains(file)) {
        String filePath = "$localPath${Platform.pathSeparator}$file";
        File uploadFile = File(filePath);
        if (uploadFile.existsSync()) {
          FileUploader uploader = FileUploader(sessionId: widget.sessionId, serverUrl: uploadServer);
          await uploader.uploadFile(filePath);
        }
      }
    }
  }

  Future<void> _downloadFiles(List<String> localFiles, List<String> cloudFiles, List<String> cloudFileCodes, String localPath) async {
    for (int i = 0; i < cloudFiles.length; i++) {
      String file = cloudFiles[i];
      if (!localFiles.contains(file)) {
        String downloadLink = await _getDownloadLink(cloudFileCodes[i]);
        var response = await http.get(Uri.parse(downloadLink));
        if (response.statusCode == 200) {
          File localFile = File("$localPath${Platform.pathSeparator}$file");
          await localFile.writeAsBytes(response.bodyBytes);
          print("Downloaded: $file");
        }
      }
    }
  }

  Future<void> _deleteCloudExtras(List<String> localFiles, List<String> cloudFiles, List<String> cloudFileCode) async {
    for (int i = 0; i < cloudFiles.length; i++) {
      String file = cloudFiles[i];
      if (!localFiles.contains(file)) {
        await http.get(Uri.parse('https://filelu.com/api/file/remove?file_code=${cloudFileCode[i]}&remove=1&sess_id=${widget.sessionId}'));
        print("Deleted from cloud: $file");
      }
    }
  }

  Future<void> _deleteLocalExtras(List<String> localFiles, List<String> cloudFiles, String localPath) async {
    for (int i = 0; i < localFiles.length; i++) {
      String file = localFiles[i];
      if (!cloudFiles.contains(file)) {
        String filePath = "$localPath${Platform.pathSeparator}$file";
        final deletefile = File(filePath);
        if (await deletefile.exists()) {
          await deletefile.delete();
          print('File deleted: $filePath');
        } else {
          print('File not found: $filePath');
        }
      }
    }
  }

  Future<String> _getDownloadLink(String fileCode) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/file/direct_link?file_code=$fileCode&sess_id=${widget.sessionId}'),
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['result']['url'];
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sync Files & Folders')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSyncOrderDialog,
        child: Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: syncOrders.length,
              itemBuilder: (context, index) {
                final order = syncOrders[index];
                return ListTile(
                  title: Text(order.syncType),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(order.localPath),
                      SizedBox(width: 50),
                      Text(order.remotePath),
                      SizedBox(width: 20),
                      // Start/Stop Button
                      IconButton(
                        icon: Icon(order.isRunning ? Icons.pause : Icons.play_arrow),
                        onPressed: () => _toggleSync(index),
                      ),
                      // Delete Button
                      IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () => _deleteSyncOrder(index),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Video Player Screen
class VideoPlayerScreen extends StatefulWidget {
  final File videoFile;
  VideoPlayerScreen({required this.videoFile});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Video Player")),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying ? _controller.pause() : _controller.play();
          });
        },
        child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}

class FileUploader {
  final String? serverUrl; // Stores the available server URL
  final String sessionId;

  FileUploader({required this.sessionId, required this.serverUrl});
  /// Fetch available upload server URL at startup
  

  /// Upload file to server
  Future<void> uploadFile(String filePath) async {
    if (serverUrl == null) {
      print("No available upload server. Upload failed.");
      return;
    }

    try {
      var request = http.MultipartRequest('POST', Uri.parse(serverUrl!));
      request.fields.addAll({
        'utype': 'prem',
        'sess_id': sessionId,
      });

      request.files.add(await http.MultipartFile.fromPath('file_0', filePath));

      http.StreamedResponse response = await request.send();

      if (response.statusCode == 200) {
        print("Upload successful: ${await response.stream.bytesToString()}");
      } else {
        print("Upload failed: ${response.reasonPhrase}");
      }
    } catch (e) {
      print("Upload error: $e");
    }
  }
}
