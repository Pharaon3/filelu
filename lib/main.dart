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
import 'package:url_launcher/url_launcher.dart';
import 'package:local_auth/local_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  
  Future<String?> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sessionId');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: FutureBuilder<String?>(
        future: getSessionId(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(body: Center(child: CircularProgressIndicator()));
          } else if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
            return MyFilesPage(sessionId: snapshot.data!);
          } else {
            return LoginPage();
          }
        },
      ),
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
  bool isLoading = false;

  void _getRequestToken(String email) async {
    setState(() {
      isLoading = true;
    });
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
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: isLoading
            ? Center(child: CircularProgressIndicator(),) // Show loading indicator
            : Center( // Centers the entire form
        child: SingleChildScrollView( // Prevents overflow on small screens
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox( // Sets a max width to avoid stretching on large screens
              constraints: BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min, // Prevents unnecessary expansion
                children: [
                  if (!isOtpPage)
                    Column(
                      children: [
                        TextField(
                          controller: _emailController,
                          decoration: InputDecoration(labelText: 'Email'),
                        ),
                        SizedBox(height: 30),
                        if (noEmail)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () async {
                              final Uri url = Uri.parse("https://filelu.com/forgot_pass");
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              } else {
                                print("Could not launch Forgot Password link");
                              }
                            },
                            child: Text("Forgot Password?", style: TextStyle(color: Colors.blue)),
                          ),
                        ),
                        SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
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
                            ElevatedButton(
                              onPressed: () async {
                                final Uri url = Uri.parse("https://filelu.com/register/");
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                } else {
                                  print("Could not launch Sign Up link");
                                }
                              },
                              child: Text("Sign Up", style: TextStyle(color: Colors.blue)),
                            ),
                          ],
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
          ),
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

  Future<void> setSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('sessionId', sessionId);
  }

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
        setSessionId(sessionId);
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
        SizedBox(height: 30),
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
  dynamic copiedFileFolder;
  int copyStatus = 0; // 0: empty, 1: file copied 2: file moved 3: folder copied 4: folder moved
  bool isLoading = false;
  bool _onlyWifiSync = true;
  bool _autoCameraBackup = false;
  String? _uploadServerURL; // Store URL globally
  String uploadServer = "";
  int numberOfImages = 0;
  int currentPage = 0;

  @override
  void initState() {
    super.initState();
    _fetchFilesAndFolders(0);
    _initializeServerUrl();
    _loadSettings();
  }

  Future<void> _initializeServerUrl() async {
    try {
      final response = await http.get(
        Uri.parse('https://filelu.com/api/upload/server?sess_id=${widget.sessionId}'),
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

  // Fetch files and folders using the API
  Future<void> _fetchFilesAndFolders(fldId) async {
    print('fetch file folder of which folder id is $fldId.');
    setState(() {
      isLoading = true; // Start loading
    });
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=${fldId.toString()}&sess_id=${widget.sessionId}'),
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
    setState(() {
      isLoading = false; // Start loading
    });
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
        return UploadPage(sessionId: widget.sessionId,);
      default:
        return _buildFileFolderList();
    }
  }

  // Display file/folder list with options
  Widget _buildFileFolderList() {
    int itemsPerPage = numberOfImages; // This should be set based on your requirement
    int totalItems = folders.length + files.length; // Total items count
    List<dynamic> _getPaginatedItems() {
      if (itemsPerPage == 0) {
        return [...folders, ...files]; // No limit
      }

      int startIndex = currentPage * itemsPerPage;
      int endIndex = startIndex + itemsPerPage;

      return [...folders, ...files].sublist(
        startIndex,
        endIndex > (folders.length + files.length) ? (folders.length + files.length) : endIndex,
      );
    }

    // Function to show the dialog
    void _showGoToPageDialog(BuildContext context) {
      final TextEditingController controller = TextEditingController();
      
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Go to Page"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: "Enter page number",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  int? page = int.tryParse(controller.text);
                  if (page != null && page > 0 && page <= ((folders.length + files.length) / itemsPerPage).ceil()) {
                    setState(() {
                      currentPage = page - 1; // Update currentPage
                    });
                    Navigator.of(context).pop(); // Close dialog
                  } else {
                    // Optionally show an error message
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Invalid page number")),
                    );
                  }
                },
                child: Text("Go to"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                },
                child: Text("Cancel"),
              ),
            ],
          );
        },
      );
    }

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
          IconButton(
            icon: Icon(Icons.more_vert), // "..." button
            onPressed: () {
              _showConfigMenu();
            },
          ),
        ],
      ),
      floatingActionButton:  copyStatus != 0
          ? FloatingActionButton(
              onPressed: _pasteFile,
              child: Icon(Icons.paste),
            )
          : null, // Returns null if copyStatus is 0
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                if (_getPaginatedItems().isNotEmpty) ...[
                  // Display Folders
                  if (folders.isNotEmpty)
                    ..._getPaginatedItems().where((item) => !item.containsKey('file_code')).map((folder) {
                      return FileFolder(
                        name: folder['name'],
                        isFile: false,
                        thumbnail: Icon(Icons.folder, size: 40),
                        onOptionsTap: () => _showOptions(context, folder),
                        onOpenFileFolder: () => _openCloudFolder(context, folder),
                      );
                    }).toList(),

                  // Display Files
                  if (files.isNotEmpty)
                    ..._getPaginatedItems().where((item) => item.containsKey('file_code')).map((file) {
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
          ),

          // Pagination Controls
          if ((folders.length + files.length) > itemsPerPage && itemsPerPage > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: currentPage > 0
                      ? () {
                          setState(() {
                            currentPage--;
                          });
                        }
                      : null,
                  child: Text("Previous"),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Open dialog when tapping the button
                    _showGoToPageDialog(context);
                  },
                  child: Text(
                    "Page ${currentPage + 1} of ${((folders.length + files.length) / itemsPerPage).ceil()}",
                  ),
                ),

                ElevatedButton(
                  onPressed: (currentPage + 1) * itemsPerPage < (folders.length + files.length)
                      ? () {
                          setState(() {
                            currentPage++;
                          });
                        }
                      : null,
                  child: Text("Next"),
                ),
              ],
            ),
            SizedBox(height: 16), // Optional spacing
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
            _showRenameDialog(context, item);
            print('Rename ${item['name']}');
          },
          onCopy: () {
            Navigator.pop(context);
            _copyFile(item, 1);
            print('Copy ${item['name']}');
          },
          onMove: () {
            Navigator.pop(context);
            _copyFile(item, 2);            
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
            _removeFile(item);
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

  void _showRenameDialog(BuildContext context, dynamic item) {
    TextEditingController controller = TextEditingController(text: item['name']);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Rename File'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: 'Enter new name'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _renameFile(item, controller.text);
              },
              child: Text('Rename'),
            ),
          ],
        );
      },
    );
  }

  void _renameFile(dynamic item, String newName) async {
    setState(() {
      isLoading = true; // Start loading
    });
    final response;
    if (item.containsKey('file_code')) {
      String fileCode = item['file_code'].toString();
      response = await http.get(
        Uri.parse('https://filelu.com/api/file/rename?file_code=$fileCode&name=$newName&sess_id=${widget.sessionId}'),
      );
    } else if (item.containsKey('fld_id')) {
      String folderID = item['fld_id'].toString();
      response = await http.get(
        Uri.parse('https://filelu.com/api/folder/rename?fld_id=$folderID&name=$newName&sess_id=${widget.sessionId}'),
      );
    } else {
      response = {'statusCode': 404};
    }
    
    if (response.statusCode == 200) {
      await _fetchFilesAndFolders(visitedFolderIDs.last.first);
      print('Successfully rename ${item['name']} to $newName.');
    } else {
      print('Rename ${item.name} failed');
    }
    setState(() {
      isLoading = false; // Start loading
    });
  }

  void _copyFile(dynamic item, int copyOrMove) {
    print('Copying ${item['name']}');
    copiedFileFolder = item;
    copyStatus = 1;
    if (!item.containsKey('file_code')) {
      copyStatus += 2;
    }
    if (copyOrMove == 2) {
      copyStatus ++;
    }
    // Add logic to duplicate the file in your data source
  }

  void _pasteFile() async {
    setState(() {
      isLoading = true; // Start loading
    });
    print("paste file.");
    String folderID = visitedFolderIDs.last.first.toString();
    if (copyStatus == 1) {  // copy file.
      print("copy file.");
      String fileCode = copiedFileFolder['file_code'];
      final response = await http.get(
        Uri.parse('https://filelu.com/api/file/clone?file_code=$fileCode&sess_id=${widget.sessionId}'),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        String clonedFileCode = data['result']['filecode'];
        final response1 = await http.get(
          Uri.parse('https://filelu.com/api/file/set_folder?file_code=$clonedFileCode&fld_id=$folderID&sess_id=${widget.sessionId}'),
        );
        if (response1.statusCode == 200) {
          print('Successfully copied.');
        } else {
          print("Failed to paste file, it's cloned to the root directory.");
        }
      } else {
        print('Failed to copy file');
        return;
      }
    } else if (copyStatus == 2) { // move file.
      print("move file.");
      String fileCode = copiedFileFolder['file_code'];
        final response = await http.get(
          Uri.parse('https://filelu.com/api/file/set_folder?file_code=$fileCode&fld_id=$folderID&sess_id=${widget.sessionId}'),
        );
        if (response.statusCode == 200) {
          print('Successfully moved.');
        } else {
          print("Failed to paste file.");
        }
    } else if (copyStatus == 3) { // copy folder.
      print("copy folder.");
      String copyFolderID = copiedFileFolder['fld_id'].toString();
      final response = await http.get(
        Uri.parse('https://filelu.com/api/folder/copy?fld_id=$copyFolderID&sess_id=${widget.sessionId}'),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        String clonedFolderID = data['result']['fld_id'].toString();
        final response1 = await http.get(
          Uri.parse('https://filelu.com/api/folder/move?fld_id=$clonedFolderID&dest_fld_id=$folderID&sess_id=${widget.sessionId}'),
        );
        if (response1.statusCode == 200) {
          String copiedFolderID = jsonDecode(response.body)['result']['fld_id'].toString();
          _renameFile(jsonDecode(response.body)['result'], copiedFileFolder['name']);
          print('Successfully copied.');
        } else {
          print("Failed to paste folder, it's cloned to the root directory.");
        }
      }
    } else if (copyStatus == 4) { // move folder.
      print("move folder.");
      String moveFolderID = copiedFileFolder['fld_id'];
      final response1 = await http.get(
        Uri.parse('https://filelu.com/api/folder/move?fld_id=$moveFolderID&dest_fld_id=$folderID&sess_id=${widget.sessionId}'),
      );
      if (response1.statusCode == 200) {
        print('Successfully moved.');
      } else {
        print("Failed to move.");
      }
    } else {
      print('Nothing to paste.');
    }
    copyStatus = 0;
    copiedFileFolder = Null;
    _fetchFilesAndFolders(visitedFolderIDs.last.first.toString());
  }

  void _removeFile(dynamic item) async {
    setState(() {
      isLoading = true; // Start loading
    });
    if(item.containsKey('file_code')) {
      String fileCode = item['file_code'].toString();
      final response = await http.get(
        Uri.parse('https://filelu.com/api/file/remove?file_code=$fileCode&remove=1&sess_id=${widget.sessionId}'),
      );
      if (response.statusCode == 200) {
        print('Successfully removed.');
      } else {
        print("Failed to remove.");
      }
    } else {
      String folderID = item['file_code'].toString();
      final response = await http.get(
        Uri.parse('https://filelu.com/api/folder/delete?fld_id=$folderID&sess_id=${widget.sessionId}'),
      );
      if (response.statusCode == 200) {
        print('Successfully removed.');
      } else {
        print("Failed to remove.");
      }
    }
    _fetchFilesAndFolders(visitedFolderIDs.last.first.toString());
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
  Future<dynamic> fetchFilesAndFolders(fldId) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=${fldId.toString()}&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['result'];
    } else {
      print('Failed to load folders and files');
      return [];
    }
  }

  void _showConfigMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SingleChildScrollView(
          child:Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sync Options
              ListTile(
                leading: Icon(Icons.wifi),
                title: Text("Only Sync Over Wi-Fi"),
                trailing: Switch(
                  value: _onlyWifiSync,
                  onChanged: (val) {
                    _toggleWifiSync(val);
                    Navigator.pop(context);
                  },
                ),
              ),
              ListTile(
                leading: Icon(Icons.backup),
                title: Text("Auto Camera Roll Backup"),
                trailing: Switch(
                  value: _autoCameraBackup,
                  onChanged: (val) {
                    setState(() => _autoCameraBackup = val);
                    Navigator.pop(context);
                    _toggleCameraBackup(val);
                  },
                ),
              ),

              // Security Options
              ListTile(
                leading: Icon(Icons.lock),
                title: Text("App Lock (Password/Face ID)"),
                onTap: _enableAppLock,
              ),

              ListTile(
                leading: Icon(Icons.pageview),
                title: Text("Set Number Of Images Per Page"),
                onTap: _showSetNumberOfImagesPerPage,
              ),

              // About & Legal
              ListTile(
                leading: Icon(Icons.info),
                title: Text("About Us"),
                onTap: () => _openURL("https://filelu.com"),
              ),
              ListTile(
                leading: Icon(Icons.article),
                title: Text("Terms"),
                onTap: () => _openURL("https://filelu.com/pages/terms/"),
              ),
              ListTile(
                leading: Icon(Icons.privacy_tip),
                title: Text("Privacy Policy"),
                onTap: () => _openURL("https://filelu.com/pages/privacy-policy/"),
              ),

              // Logout
              ListTile(
                leading: Icon(Icons.logout),
                title: Text("Log Out"),
                onTap: ()=> _logout(context),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBackupOptions() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Auto Camera Roll Backup"),
          content: Text("Start backup from:"),
          actions: [
            TextButton(
              onPressed: () {
                _startBackup(fromToday: true);
                Navigator.pop(context);
              },
              child: Text("Today Only"),
            ),
            TextButton(
              onPressed: () {
                _startBackup(fromToday: false);
                Navigator.pop(context);
              },
              child: Text("From Beginning"),
            ),
          ],
        );
      },
    );
  }

  void _showSetNumberOfImagesPerPage() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Set Number Of Images Per Page"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Default 0: no limitation"),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Enter Number",
                  hintText: "e.g. 10",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Handle the input value
                int? enteredNumberOfImages = int.tryParse(controller.text);
                if (enteredNumberOfImages != null) {
                  // Use the number as needed
                  setState(() {
                    numberOfImages = enteredNumberOfImages;
                    currentPage = 0;
                  });
                  print("Number of images per page: $enteredNumberOfImages");
                } else {
                  // Handle invalid input
                  print("Invalid input. Please enter a valid number.");
                }
                Navigator.of(context).pop(); // Close the dialog
              },
              child: Text("Set"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _onlyWifiSync = prefs.getBool('onlyWifiSync') ?? true;
      _autoCameraBackup = prefs.getBool('autoCameraBackup') ?? false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _toggleWifiSync(bool value) {
    setState(() {
      _onlyWifiSync = value;
    });
    _saveSetting('onlyWifiSync', value);
  }

  void _toggleCameraBackup(bool value) {
    setState(() {
      _autoCameraBackup = value;
    });
    _saveSetting('autoCameraBackup', value);

    if (value) {
      _showBackupOptions();
    }
  }

  void _openURL(String url) async {
    Uri uri = Uri.parse(url);

    if (Platform.isWindows) {
      // Use `Process.start` on Windows instead of `launchUrl`
      await Process.start('explorer.exe', [url]);
    } else {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print("❌ Could not open: $url");
      }
    }
  }

  Future<void> _enableAppLock() async {
    final localAuth = LocalAuthentication();
    bool canAuthenticate = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();

    if (canAuthenticate) {
      bool didAuthenticate = await localAuth.authenticate(
        localizedReason: 'Please authenticate to enable App Lock',
      );

      if (didAuthenticate) {
        print("App Lock Enabled");
        // Save lock setting in SharedPreferences
        _saveSetting('appLock', true);
      }
    } else {
      print("Biometric authentication not available");
    }
  }

  void _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('sessionId', "");
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => LoginPage()),
      (Route<dynamic> route) => false, // Removes all previous routes
    );
  }

  Future<void> _startBackup({required bool fromToday}) async {
    final directory = await _getCameraRollDirectory();
    if (directory == null) {
      print("Camera Roll folder not found");
      return;
    }

    List<FileSystemEntity> mediaFiles = directory.listSync().where(
      (file) {
        if (file is File) {
          final ext = file.path.split('.').last.toLowerCase();
          return ["jpg", "jpeg", "png", "mp4", "mov"].contains(ext);
        }
        return false;
      },
    ).toList();

    if (fromToday) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      mediaFiles = mediaFiles.where((file) {
        return FileStat.statSync(file.path).modified.isAfter(DateTime.parse(today));
      }).toList();
    }

    for (var file in mediaFiles) {
      FileUploader uploader = FileUploader(sessionId: widget.sessionId, serverUrl: uploadServer);
      String fileCode = await uploader.uploadFile(file.path);
      String cameraFolderID = await uploader.getFolderID("Camera", "0");
      if (cameraFolderID == "") {
        cameraFolderID = await uploader.createCloudFolder("Camera", "0");
      }
      await uploader.moveFile(fileCode, cameraFolderID);
      // await _uploadFileToCloud(file.path);
    }

    print("Backup completed: ${mediaFiles.length} files uploaded");
  }

  Future<Directory?> _getCameraRollDirectory() async {
    if (Platform.isAndroid) {
      return Directory("/storage/emulated/0/DCIM/Camera");
    } else if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return Directory("${dir.path}/DCIM");
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      return Directory("$userProfile\\Pictures\\Camera Roll");
    } else {
      return null;
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
  String fld_id;

  SyncOrder({
    required this.localPath,
    required this.syncType,
    this.isRunning = false,
    required this.remotePath,
    required this.fld_id,
  });

  // Convert SyncOrder to JSON
  Map<String, dynamic> toJson() {
    return {
      'localPath': localPath,
      'syncType': syncType,
      'isRunning': isRunning,
      'remotePath': remotePath,
      'fld_id': fld_id,
    };
  }

  // Create SyncOrder from JSON
  factory SyncOrder.fromJson(Map<String, dynamic> json) {
    return SyncOrder(
      localPath: json['localPath'],
      syncType: json['syncType'],
      isRunning: json['isRunning'] ?? false,
      remotePath: json['remotePath'],
      fld_id: json['fld_id'],
    );
  }
}

class _SyncPageState extends State<SyncPage> {
  List<SyncOrder> syncOrders = [];
  List<List<String>> syncedFiles = [];
  String uploadServer = "";
  dynamic syncedFileFolders = {};
  final String sessionId;
  bool isLoading = false;

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
    final dynamic? storedSyncedFileFolders = prefs.getString('scanned_data');

    if (storedOrders != null && storedOrders != "" && storedOrders != {}) {
      setState(() {
        List<dynamic> decoded = jsonDecode(storedOrders);
        syncOrders = decoded.map((e) => SyncOrder.fromJson(e)).toList();
      });
    }

    if (storedSyncedFiles != null && storedSyncedFiles != "" && storedSyncedFiles != {}) {
      setState(() {
        List<dynamic> decoded = jsonDecode(storedSyncedFiles);
        syncedFiles = decoded.map((e) => List<String>.from(e)).toList();
      });
    }

    if (storedSyncedFileFolders != null && storedSyncedFileFolders != "" && storedSyncedFileFolders != {}) {
      setState(() {
        syncedFileFolders = jsonDecode(storedSyncedFileFolders);
      });
    }
  }

  /// Save sync orders to local storage
  Future<void> _saveSyncOrders() async {
    final prefs = await SharedPreferences.getInstance();
    String encodedOrders = jsonEncode(syncOrders.map((e) => e.toJson()).toList());
    await prefs.setString('sync_orders', encodedOrders);
  }

  Future<void> _saveGlobal(key, value) async {
    final prefs = await SharedPreferences.getInstance();
    String encodedOrders = jsonEncode(value);
    await prefs.setString(key, encodedOrders);
  }

  /// Add new Sync Order
  void _addSyncOrder(String localPath, String syncType, String remotePath) async {
    List<String> remotePathList = remotePath.split("/");
    String currentRemoteFldID = "0";
    for (int i = 0; i < remotePathList.length; i ++) {
      String currentRemotePath = remotePathList[i];
      if (currentRemotePath == "") break;
      currentRemoteFldID = await getFolderID(currentRemotePath, currentRemoteFldID);
      if (currentRemoteFldID == "") return;
    }
    setState(() {
      syncOrders.add(SyncOrder(localPath: localPath, syncType: syncType, remotePath: remotePath, fld_id: currentRemoteFldID));
      _toggleSync(syncOrders.length - 1);
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
        return StatefulBuilder(
          builder: (context, setState) { // Add StatefulBuilder here
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
                      setState(() => selectedType = value!); // Use local setState
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
    print("perform orders");
    print(order);
    switch (order.syncType) {
      case "Upload Only":
        await _uploadFiles(order.localPath, order.fld_id);
        break;
      case "Download Only":
        await _downloadFiles(order.localPath, order.fld_id);
        break;
      case "One-Way Sync":
        await _onewaySync(order.localPath, order.fld_id);
        break;
      case "Two-Way Sync":
        await _twowaySync(order.localPath, order.fld_id, _findFolderData(syncedFileFolders, order.fld_id));
        break;
    }

    dynamic scanedData = await _scanCloudFiles("", "0");
    syncedFileFolders = scanedData;
    _saveGlobal('scaned_data', scanedData);

  }

  Future<void> _uploadFiles(String localPath, String folderID) async {
    List<String> cloudFiles = [];
    List<String> cloudFolders = [];
    List<String> cloudFileCodes = [];
    List<String> cloudFolderCodes = [];
    List<String> localFiles = [];
    List<String> localFolders = [];

    Directory dir = Directory(localPath);
    if (dir.existsSync()) {
      localFiles = dir.listSync().whereType<File>().map((e) => e.path.split(Platform.pathSeparator).last).toList();
      localFolders = dir
        .listSync()
        .whereType<Directory>()
        .map((folder) => folder.path.split(Platform.pathSeparator).last)
        .toList();
    }
    
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$folderID&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
      cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code']));
      cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
      cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));
    }

    for (String file in localFiles) {
      if (!cloudFiles.contains(file)) {
        String filePath = "$localPath${Platform.pathSeparator}$file";
        File uploadFile = File(filePath);
        if (uploadFile.existsSync()) {
          FileUploader uploader = FileUploader(sessionId: widget.sessionId, serverUrl: uploadServer);
          String fileCode = await uploader.uploadFile(filePath);
          await uploader.moveFile(fileCode, folderID);
        }
      }
    }

    for (String localFolder in localFolders) {
      if (!cloudFolders.contains(localFolder)) {
        String newFoldeId = await createCloudFolder(localFolder, folderID);
        _uploadFiles("$localPath/$localFolder", newFoldeId);
      } else {
        _uploadFiles("$localPath/$localFolder", cloudFolderCodes[cloudFolders.indexOf(localFolder)]);
      }
    }

  }

  Future<void> _downloadFiles(String localPath, String folderID) async {
    List<String> cloudFiles = [];
    List<String> cloudFolders = [];
    List<String> cloudFileCodes = [];
    List<String> cloudFolderCodes = [];
    List<String> localFiles = [];
    List<String> localFolders = [];

    Directory dir = Directory(localPath);
    if (dir.existsSync()) {
      localFiles = dir.listSync().whereType<File>().map((e) => e.path.split(Platform.pathSeparator).last).toList();
      localFolders = dir
        .listSync()
        .whereType<Directory>()
        .map((folder) => folder.path.split(Platform.pathSeparator).last)
        .toList();
    }
    
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$folderID&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
      cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code']));
      cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
      cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));
    }

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

    for (int i = 0; i < cloudFolders.length; i++) {
      String cloudFolder = cloudFolders[i];
      String cloudFolderCode = cloudFolderCodes[i];
      createFolderIfNotExists("$localPath${Platform.pathSeparator}$cloudFolder");
      _downloadFiles("$localPath${Platform.pathSeparator}$cloudFolder", cloudFolderCode);
    }

  }

  Future<void> _onewaySync(String localPath, String folderID) async {
    List<String> cloudFiles = [];
    List<String> cloudFolders = [];
    List<String> cloudFileCodes = [];
    List<String> cloudFolderCodes = [];
    List<String> localFiles = [];
    List<String> localFolders = [];

    Directory dir = Directory(localPath);
    if (dir.existsSync()) {
      localFiles = dir.listSync().whereType<File>().map((e) => e.path.split(Platform.pathSeparator).last).toList();
      localFolders = dir
        .listSync()
        .whereType<Directory>()
        .map((folder) => folder.path.split(Platform.pathSeparator).last)
        .toList();
    }
    
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$folderID&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
      cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code']));
      cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
      cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));
    }

    for (String file in localFiles) {
      if (!cloudFiles.contains(file)) {
        String filePath = "$localPath${Platform.pathSeparator}$file";
        File uploadFile = File(filePath);
        if (uploadFile.existsSync()) {
          FileUploader uploader = FileUploader(sessionId: widget.sessionId, serverUrl: uploadServer);
          String fileCode = await uploader.uploadFile(filePath);
          await uploader.moveFile(fileCode, folderID);
        }
      }
    }

    for (int i = 0; i < cloudFiles.length; i++) {
      String file = cloudFiles[i];
      if (!localFiles.contains(file)) {
        await http.get(Uri.parse('https://filelu.com/api/file/remove?file_code=${cloudFileCodes[i]}&remove=1&sess_id=${widget.sessionId}'));
        print("Deleted from cloud: $file");
      }
    }

    for (String localFolder in localFolders) {
      if (!cloudFolders.contains(localFolder)) {
        String newFoldeId = await createCloudFolder(localFolder, folderID);
        _onewaySync("$localPath/$localFolder", newFoldeId);
      } else {
        _onewaySync("$localPath/$localFolder", cloudFolderCodes[cloudFolders.indexOf(localFolder)]);
      }
    }

  }

  Future<void> _twowaySync(String localPath, String folderID, dynamic folderData) async {
    print("two way sync");
    print(localPath);
    print(folderID);
    List<String> cloudFiles = [];
    List<String> cloudFolders = [];
    List<String> cloudFileCodes = [];
    List<String> cloudFolderCodes = [];
    List<String> localFiles = [];
    List<String> localFolders = [];
    List<String> syncFiles = [];
    List<dynamic> syncFolders = [];
    List<String> syncFileCodes = [];
    List<String> syncFolderCodes = [];

    if (folderData == {} || folderData == null || folderData == "") {
      _uploadFiles(localPath, folderID);
      _downloadFiles(localPath, folderID);
      return;
    }

    if (!folderData.containsKey('file') && !folderData.containsKey('folder')) {
      _uploadFiles(localPath, folderID);
      _downloadFiles(localPath, folderID);
      return;
    }

    if (folderData.containsKey('file')) syncFiles = folderData['file'].keys.toList();
    if (folderData.containsKey('file')) syncFileCodes = folderData['file'].values.toList();
    if (folderData.containsKey('folder')) syncFolders = folderData['folder'];

    List<String> syncFolderNames = syncFolders.map((folder) => folder['folder_name'] as String).toList();
    syncFolderCodes = syncFolders.map((folder) => folder['folder_id'] as String).toList();
    List<dynamic> syncFolderDatas = syncFolders.map((folder) => folder['folder_data'] as dynamic).toList();

    Directory dir = Directory(localPath);
    if (dir.existsSync()) {
      localFiles = dir.listSync().whereType<File>().map((e) => e.path.split(Platform.pathSeparator).last).toList();
      localFolders = dir
        .listSync()
        .whereType<Directory>()
        .map((folder) => folder.path.split(Platform.pathSeparator).last)
        .toList();
    }

    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$folderID&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
      cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code']));
      cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
      cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));
    }

    for (int i = 0; i < cloudFiles.length; i ++) {
      String file = cloudFiles[i];
      if (!syncFiles.contains(file)) {
        String downloadLink = await _getDownloadLink(cloudFileCodes[i]);
        var responseDownload = await http.get(Uri.parse(downloadLink));
        if (responseDownload.statusCode == 200) {
          File localFile = File("$localPath${Platform.pathSeparator}$file");
          await localFile.writeAsBytes(responseDownload.bodyBytes);
          print("Downloaded: $file");
        }
      }
    }

    for (String file in localFiles) {
      if (!syncFiles.contains(file)) {
        String filePath = "$localPath${Platform.pathSeparator}$file";
        File uploadFile = File(filePath);
        if (uploadFile.existsSync()) {
          FileUploader uploader = FileUploader(sessionId: widget.sessionId, serverUrl: uploadServer);
          String fileCode = await uploader.uploadFile(filePath);
          await uploader.moveFile(fileCode, folderID);
        }
      }
    }

    for (int i = 0; i < syncFiles.length; i ++) {
      String file = syncFiles[i];
      if(!localFiles.contains(file)) {
        String fileToDeleteCode = syncFileCodes[i];
        await http.get(Uri.parse('https://filelu.com/api/file/remove?file_code=$fileToDeleteCode&remove=1&sess_id=${widget.sessionId}'));
        print("Deleted from cloud: $file");
      }
      if(!cloudFiles.contains(file)) {
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

    for (int i = 0; i < cloudFolders.length; i ++) {
      String folder = cloudFolders[i];
      String folderCode = cloudFolderCodes[i];
      if (!syncFolderNames.contains(folder)) {
        await createFolderIfNotExists("$localPath${Platform.pathSeparator}$folder");
        await _downloadFiles("$localPath${Platform.pathSeparator}$folder", folderCode);
      }
    }

    for (String folder in localFolders) {
      if (!syncFolderNames.contains(folder)) {
        if (!cloudFolders.contains(folder)) {
          String newFoldeId = await createCloudFolder(folder, folderID);
          await _uploadFiles("$localPath/$folder", newFoldeId);
        } else {
          await _uploadFiles("$localPath/$folder", cloudFolderCodes[cloudFolders.indexOf(folder)]);
        }
      }
    }

    for (int i = 0; i < syncFolderNames.length; i ++) {
      String folder = syncFolderNames[i];
      if (!localFolders.contains(folder)) {
        await _deleteCloudFolder(syncFolderCodes[i]);
      } else if (!cloudFolders.contains(folder)) {
        await _deleteLocalFolder("$localPath/$folder");
      } else {
        await _twowaySync("$localPath/$folder", syncFolderCodes[i], syncFolderDatas[i]);
      }
    }

  }

  Future<dynamic> _scanCloudFiles(String folderName, String fldID) async {
    dynamic scanedData = {};
    // Update synced files.
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$fldID&sess_id=${widget.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      List<String> cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
      List<String> cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code'].toString()));
      List<String> cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
      List<String> cloudFolderIDs = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));
      scanedData['file'] = cloudFiles.asMap().map((i, f) => MapEntry(f, cloudFileCodes[i]));
      scanedData['folder'] = [];
      for (int i = 0; i < cloudFolders.length; i ++) {
        String cloudFolder = cloudFolders[i];
        String cloudFolderID = cloudFolderIDs[i];
        dynamic cloudFolderData = await _scanCloudFiles(cloudFolder, cloudFolderID);
        scanedData['folder'].add(cloudFolderData);
      }
    }
    return {"folder_name": folderName, "folder_id": fldID, "folder_data": scanedData};

  }

  dynamic _findFolderData(dynamic fileFolder, String fldID) {
    // Check if fileFolder is empty
    if (fileFolder.isEmpty) return null; // Changed to return null for easier checks

    // Check if the current folder matches the fldID
    if (fileFolder['folder_id'] == fldID) return fileFolder['folder_data'];

    // Check if folder_data exists and is a map
    if (!fileFolder.containsKey('folder_data') || 
        fileFolder['folder_data'] is! Map) return null;

    // Iterate over the list of folders in folder_data
    var folders = fileFolder['folder_data']['folder'];
    if (folders is! List) return null; // Ensure it's a list

    for (dynamic newFileFolder in folders) {
      dynamic tmpFolderData = _findFolderData(newFileFolder, fldID);
      if (tmpFolderData != null) return tmpFolderData; // Check against null
    }

    return null; // Return null if not found
  }

  Future<void> _deleteLocalFolder(String folderPath) async {
      // Create a Directory object
    var directory = Directory(folderPath);

    // Check if the directory exists
    if (directory.existsSync()) {
      // Delete the directory
      directory.deleteSync(recursive: true);
      print('Folder deleted successfully.');
    } else {
      print('Folder does not exist.');
    }
  }

  Future<void> _deleteCloudFolder(String folderID) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/delete?fld_id=$folderID&sess_id=${widget.sessionId}'),
    );
    if (response.statusCode == 200) {
      print("Successfully delete cloud folder $folderID.");
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

  Future<String> getFolderID(String folderName, String parentFolderID) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$parentFolderID&sess_id=${widget.sessionId}'),
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      List<String> cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
      List<String> cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));
      for (int i = 0; i < cloudFolders.length; i ++) {
        if (cloudFolders[i] == folderName) {
          return cloudFolderCodes[i];
        }
      }
    }
    return "";
  }

  Future<String> createCloudFolder(String localFolder, String parentId) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/create?parent_id=$parentId&name=$localFolder&sess_id=${widget.sessionId}')
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['result']['fld_id'].toString();
    }
    return "";
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

  String abbreviate(String path, {int maxLength = 25}) {
    if (path.length <= maxLength) {
      return path;
    }
    int startLength = (maxLength ~/ 2) - 1; // Length of the start part
    int endLength = maxLength - startLength - 3; // Length of the end part (for "...")
    
    return '${path.substring(0, startLength)}...${path.substring(path.length - endLength)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sync Files & Folders')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSyncOrderDialog,
        child: Icon(Icons.add),
      ),
      body: isLoading
            ? Center(child: CircularProgressIndicator(),) // Show loading indicator
            : Column(
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
                      Text(abbreviate(order.localPath)),
                      SizedBox(width: 20),
                      Text("/${order.remotePath}"),
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

class UploadPage extends StatefulWidget {
  final String sessionId;
  UploadPage({required this.sessionId});

  @override
  _UploadPageState createState() => _UploadPageState(sessionId: sessionId);
}

class _UploadPageState extends State<UploadPage> {
  String uploadServer = "";
  final String sessionId;
  bool isLoading = false;
  List<String> selectedFiles = [];

  _UploadPageState({required this.sessionId});

  @override
  void initState() {
    super.initState();
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

  Future<void> uploadFiles() async{
    setState(() {
      isLoading = true;
    });
    FileUploader uploader = FileUploader(sessionId: widget.sessionId, serverUrl: uploadServer);
    for (String filePath in selectedFiles) {
      print("File $filePath is uploading now...");
      await uploader.uploadFile(filePath);
      print("File $filePath is uploaded.");
    }
    setState(() {
      selectedFiles = [];
      isLoading = false;
    });
  }
  
  Future<String> getFolderID(String folderName, String parentFolderID) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$parentFolderID&sess_id=${widget.sessionId}'),
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      List<String> cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
      List<String> cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));
      for (int i = 0; i < cloudFolders.length; i ++) {
        if (cloudFolders[i] == folderName) {
          return cloudFolderCodes[i];
        }
      }
    }
    return "";
  }

  Future<void> _pickFiles() async {
    setState(() {
      isLoading = true; // Start loading
    });

    // Pick files
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null) {
        setState(() {
          selectedFiles = result.paths.map((path) => path!).toList();
        });
      }
    } catch (e) {
      // Handle error
      print('Error picking files: $e');
    } finally {
      setState(() {
        isLoading = false; // End loading
      });
    }
  }

  Future<void> moveFile(String fileCode, String folderID) async {
    await http.get(Uri.parse('https://filelu.com/api/file/set_folder?file_code=$fileCode&fld_id=$folderID&sess_id=${widget.sessionId}'));
  }

  Future<String> createCloudFolder(String localFolder, String parentId) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/create?parent_id=$parentId&name=$localFolder&sess_id=${widget.sessionId}')
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['result']['fld_id'].toString();
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Upload Files')),
      body: isLoading
          ? Center(child: CircularProgressIndicator()) // Show loading indicator
          : Column(
              children: [
                ElevatedButton(
                  onPressed: _pickFiles,
                  child: Text('Select Files'),
                ),
                SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: selectedFiles.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(selectedFiles[index]),
                      );
                    },
                  ),
                ),
                ElevatedButton(
                  onPressed: uploadFiles,
                  child: Text('Upload Files'),
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
  Future<String> uploadFile(String filePath) async {
    if (serverUrl == null) {
      print("No available upload server. Upload failed.");
      return "";
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
        String responseString = await response.stream.bytesToString();
        print("Upload successful: $responseString");
        final List<dynamic> responseData = jsonDecode(responseString);
        return responseData[0]['file_code'];
      } else {
        print("Upload failed: ${response.reasonPhrase}");
      }
    } catch (e) {
      print("Upload error: $e");
    }
    return "";
  }
  
  Future<void> moveFile(String fileCode, String folderID) async {
    await http.get(Uri.parse('https://filelu.com/api/file/set_folder?file_code=$fileCode&fld_id=$folderID&sess_id=$sessionId'));
  }

  Future<String> getFolderID(String folderName, String parentFolderID) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/list?fld_id=$parentFolderID&sess_id=$sessionId'),
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      List<String> cloudFolders = List<String>.from(data['result']['folders'].map((folder) => folder['name']));
      List<String> cloudFolderCodes = List<String>.from(data['result']['folders'].map((folder) => folder['fld_id'].toString()));
      for (int i = 0; i < cloudFolders.length; i ++) {
        if (cloudFolders[i] == folderName) {
          return cloudFolderCodes[i];
        }
      }
    }
    return "";
  }

  Future<String> createCloudFolder(String localFolder, String parentId) async {
    final response = await http.get(
      Uri.parse('https://filelu.com/api/folder/create?parent_id=$parentId&name=$localFolder&sess_id=$sessionId')
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['result']['fld_id'].toString();
    }
    return "";
  }

}
