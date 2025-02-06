import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';

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
  List<int> prevFolderId = [0, 0];

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
  if (Platform.isAndroid) {
    return "/storage/emulated/0/Download"; // Default download folder on Android
  } else if (Platform.isIOS) {
    Directory dir = await getApplicationDocumentsDirectory();
    return dir.path;
  } else if (Platform.isWindows) {
    String? userHome = Platform.environment['USERPROFILE']; // Get user home directory
    return "$userHome\\Documents\\MySyncFolder"; // Default downloads folder in Windows
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
    return ListView(
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
            downloadFile(item['file_code'], item['name']);
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
      prevFolderId.add(item['fld_id']);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // Show text file content inside a dialog
  Future<void> openCloudFile(BuildContext context, String file_code, String fileName) async {
    try {
      String downloadLink = await _getDownloadLink(file_code);
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
      prevFolderId.removeLast();
      await _fetchFilesAndFolders(prevFolderId.last);
    } catch (e) {
      print(e);
    }
  }

  void _homeCloudFolder() async {
    try {
      prevFolderId = [0, 0];
      await _fetchFilesAndFolders(prevFolderId.last);
    } catch (e) {
      print(e);
    }
  }

  Future<void> downloadFile(String fileCode, String fileName) async {
    String saveDirectory = await getDownloadDirectory();
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
  @override
  Widget build(BuildContext context) {
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