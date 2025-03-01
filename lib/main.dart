import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:isolate';

const String baseURL = "https://filelu.com/api";

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {

  Future<String?> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sessionId');
  }

  Future<String?> _getSavedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('appLockPassword');
  }

  Future<bool> _validatePassword(BuildContext context) async {
    String? savedPassword = await _getSavedPassword();
    
    if (savedPassword == null || savedPassword.isEmpty) {
      return true; // No password set, proceed normally.
    }

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside.
      builder: (context) {
        TextEditingController passwordController = TextEditingController();
        return AlertDialog(
          title: Text("Enter App Lock Password"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "Password",
                  labelStyle: TextStyle(color: Colors.blue), // Change label color
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue, width: 2.0), // Border when focused
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false); // Reject login
              },
              child: Text(
                "Cancel",
                style: TextStyle(color: Colors.blue),
              ),
            ),
            TextButton(
              onPressed: () {
                if (passwordController.text == savedPassword) {
                  Navigator.pop(context, true); // Accept login
                } else {
                  Navigator.pop(context, false); // Wrong password
                }
              },
              child: Text(
                "Unlock",
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        );
      },
    ) ??
    false; // Default to false if dialog is dismissed.
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FileLu Sync',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: FutureBuilder<String?>(
        future: getSessionId(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            );
          } else if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
            return FutureBuilder<bool>(
              future: _validatePassword(context),
              builder: (context, passwordSnapshot) {
                if (passwordSnapshot.connectionState == ConnectionState.waiting) {
                  return Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                  );
                } else if (passwordSnapshot.data == true) {
                  return MainPage(sessionId: snapshot.data!);
                } else {
                  return LoginPage();
                }
              },
            );
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
    final response = await http.get(Uri.parse('$baseURL/session/request?email=$email'));

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
            ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)),) // Show loading indicator
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
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: TextStyle(color: Colors.blue), // Change label color
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.blue, width: 2.0), // Border when focused
                            ),
                          ),
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
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue, // Set background color to blue
                              ), // Disable button while uploading
                              child: Text(
                                'Get OTP',
                                style: TextStyle(color: Colors.white),
                              ),
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
                    Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue))), // Show loading until requestToken is available
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
  final TextEditingController _otpController = TextEditingController();

  Future<void> setSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('sessionId', sessionId);
  }

  void _startSession(String otp) async {
    // Ensure requestToken is not null before making the API call
    if (widget.requestToken.isNotEmpty && otp.isNotEmpty) {
      final response = await http.get(Uri.parse(
          '$baseURL/session/start?request_token=${widget.requestToken}&otp=$otp'));
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
          MaterialPageRoute(builder: (context) => MainPage(sessionId: sessionId)),
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
          decoration: InputDecoration(
            labelText: 'Enter OTP',
            labelStyle: TextStyle(color: Colors.blue), // Change label color
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue, width: 2.0), // Border when focused
            ),
          ),
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
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue, // Set background color to blue
          ), // Disable button while uploading
          child: Text(
            'Submit OTP',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

}

class MainPage extends StatefulWidget {
  final String sessionId;
  MainPage({required this.sessionId});

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _tabSelected = 0;
  MainFeature mainFeature = MainFeature();

  @override
  void initState() {
    super.initState();
  }

  // Handle navigation between pages
  void _onItemTapped(int index) {
    setState(() {
      _tabSelected = index;
    });
  }

  // Display different pages based on navigation selection
  Widget _getPageContent() {
    switch (_tabSelected) {
      case 0:
        return MyFilesPage(mainFeature: mainFeature,);
      case 1:
        return SyncPage(mainFeature: mainFeature,);
      case 2:
        return UploadPage(mainFeature: mainFeature,);
      case 3:
        return UploadPage(mainFeature: mainFeature,);
      default:
        return MyFilesPage(mainFeature: mainFeature,);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _getPageContent(),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        currentIndex: _tabSelected,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey, // Set the color for unselected items
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
            label: 'Transfer',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_box),
            label: 'Account',
          ),
        ],
      ),
    );
  }

}

class MyFilesPage extends StatefulWidget {
  final MainFeature mainFeature;
  MyFilesPage({required this.mainFeature});

  @override
  _MyFilesPageState createState() => _MyFilesPageState(mainFeature: mainFeature);
}

class _MyFilesPageState extends State<MyFilesPage> {
  List<dynamic> folders = [];
  List<dynamic> files = [];
  List<dynamic> visitedFolderIDs = [[0, '/'], [0, '/']];
  List<dynamic> copiedFileFolders = [];
  int copyStatus = 0; // 0: empty, 1: copied 2: moved
  bool isLoading = false;
  bool _onlyWifiSync = true;
  bool _autoCameraBackup = false;
  String uploadServer = "";
  int numberOfImages = 0;
  int currentPage = 0;
  List<dynamic> selectedItems = [];
  String errorMessage = "";
  Isolate? _backgroundIsolate;
  bool fromToday = false;
  final MainFeature mainFeature;
  DateTime lastBackupDate = DateTime.now();

  _MyFilesPageState({required this.mainFeature});

  @override
  void initState() {
    super.initState();
    _fetchFilesAndFolders(0);
    _loadSettings();
  }

  // Fetch files and folders using the API
  Future<void> _fetchFilesAndFolders(fldId) async {
    setState(() {
      isLoading = true; // Start loading
    });
    await mainFeature.initState();
    print('fetch file folder of which folder id is $fldId.');
    print('sessionId is ${mainFeature.sessionId}.');
    final response = await http.get(
      Uri.parse('$baseURL/folder/list?fld_id=${fldId.toString()}&sess_id=${mainFeature.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(utf8.decode(response.bodyBytes));
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
      Uri.parse('$baseURL/file/direct_link?file_code=$fileCode&sess_id=${mainFeature.sessionId}')
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
    String subpath = visitedFolderIDs
      .map((entry) => entry[1])
      .where((path) => path.isNotEmpty)
      .join('/');
    subpath = subpath.replaceAll(RegExp(r'/{2,}'), '/');
    if (subpath.endsWith('/')) {
      subpath = subpath.substring(0, subpath.length - 1);
    }
    if (Platform.isAndroid) {
      String path = '/storage/emulated/0/Download/FileLuSync/$subpath';
      return path;
    } else if (Platform.isIOS) {
      Directory dir = await getApplicationDocumentsDirectory();
      return "${dir.path}/$subpath"; // Add subpath here
    } else if (Platform.isWindows) {
      String? userHome = Platform.environment['USERPROFILE'];
      return "$userHome\\Documents\\MySyncFolder\\$subpath";
    } else if (Platform.isMacOS) {
      Directory dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      return "${dir.path}/$subpath"; // Add subpath here if needed
    } else if (Platform.isLinux) {
      String? home = Platform.environment['HOME'];
      return "$home/Downloads/$subpath"; // Add subpath here if needed
    } else {
      throw Exception("Unsupported platform");
    }
  }

  // Display file/folder list with options
  Widget _buildFileFolderList() {
    int itemsPerPage = numberOfImages; // Number of items per page
    int totalItems = folders.length + files.length;
    bool selectionMode = selectedItems.isNotEmpty; // Enable selection mode if items are selected

    List<dynamic> getPaginatedItems() {
      if (itemsPerPage == 0) {
        return [...folders, ...files]; // No limit
      }
      int startIndex = currentPage * itemsPerPage;
      int endIndex = startIndex + itemsPerPage;
      return [...folders, ...files].sublist(
        startIndex,
        endIndex > totalItems ? totalItems : endIndex,
      );
    }

    // Function to show the dialog
    void showGoToPageDialog(BuildContext context) {
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
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2.0), // Border when focused
                    ),
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
                child: Text("Go to", style: TextStyle(color: Colors.blue),),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                },
                child: Text("Cancel", style: TextStyle(color: Colors.blue),),
              ),
            ],
          );
        },
      );
    }

    void toggleSelectionMode(Map<String, dynamic> item) {
      setState(() {
        if (selectedItems.contains(item)) {
          selectedItems.remove(item);
          if (selectedItems.isEmpty) selectionMode = false;
        } else {
          selectedItems.add(item);
          selectionMode = true;
        }
      });
    }

    Icon getFileIcon(String fileName) {
      String extension = fileName.split('.').last.toLowerCase();
      
      switch (extension) {
        case 'jpg':
        case 'jpeg':
        case 'png':
        case 'gif':
          return Icon(Icons.image, color: Colors.blue);
        case 'mp3':
        case 'wav':
          return Icon(Icons.audiotrack, color: Colors.red);
        case 'mp4':
        case 'mov':
          return Icon(Icons.videocam, color: Colors.green);
        case 'txt':
          return Icon(Icons.description, color: Colors.orange);
        case 'pdf':
          return Icon(Icons.picture_as_pdf, color: Colors.purple);
        default:
          return Icon(Icons.insert_drive_file, color: Colors.grey); // Default icon for unknown types
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(selectionMode ? "${selectedItems.length} selected" : 'My Files'),
        leading: IconButton(
          icon: Icon(selectionMode ? Icons.close : Icons.arrow_back, color: Colors.blue,),
          onPressed: () {
            if (selectionMode) {
              setState(() {
                selectedItems.clear();
              });
            } else {
              _backCloudFolder();
            }
          },
        ),
        actions: [
          if (!selectionMode) ...[
            IconButton(
              icon: Icon(Icons.home, color: Colors.blue),
              onPressed: () => _homeCloudFolder(),
            ),
            IconButton(
              icon: Icon(Icons.more_vert),
              onPressed: () => _showConfigMenu(),
            ),
          ] else ...[
            IconButton(
              icon: Icon(Icons.select_all, color: Colors.blue),
              onPressed: () {
                setState(() {
                  if (selectedItems.length == totalItems) {
                    selectedItems.clear();
                    selectionMode = false;
                  } else {
                    selectedItems = List.from([...folders, ...files]);
                    selectionMode = true;
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.more_vert),
              onPressed: () {
                setState(() {
                  selectionMode = false;
                });
                _showOptions(context, "");
              },
            ),
          ],
        ],
      ),
      floatingActionButton: copyStatus != 0
          ? FloatingActionButton(
              onPressed: _pasteFile,
              child: Icon(Icons.paste, color: Colors.blue),
            )
          : null,
      body: isLoading
          ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      if (getPaginatedItems().isNotEmpty) ...[
                        // Display Folders
                        if (folders.isNotEmpty)
                          ...getPaginatedItems()
                              .where((item) => !item.containsKey('file_code'))
                              .map((folder) {
                            bool isSelected = selectedItems.contains(folder);
                            return GestureDetector(
                              onLongPress: () => toggleSelectionMode(folder),
                              onTap: () {
                                if (selectionMode) {
                                  toggleSelectionMode(folder);
                                } else {
                                  _openCloudFolder(context, folder);
                                }
                              },
                              child: ListTile(
                                leading: Icon(Icons.folder, size: 40, color: isSelected ? Colors.cyan : Colors.blue),
                                title: Text(folder['name']),
                                trailing: IconButton(
                                  icon: Icon(
                                    selectionMode
                                        ? (isSelected ? Icons.check_circle : Icons.radio_button_unchecked)
                                        : Icons.more_vert,
                                    color: isSelected ? Colors.blue : null,
                                  ),
                                  onPressed: selectionMode
                                      ? () => toggleSelectionMode(folder)
                                      : () => _showOptions(context, folder),
                                ),
                              ),
                            );
                          }).toList(),

                        // Display Files
                        if (files.isNotEmpty)
                          ...getPaginatedItems().where((item) => item.containsKey('file_code')).map((file) {
                            bool isSelected = selectedItems.contains(file);
                            return GestureDetector(
                              onLongPress: () => toggleSelectionMode(file),
                              onTap: () {
                                if (selectionMode) {
                                  toggleSelectionMode(file);
                                } else {
                                  openCloudFile(context, file['file_code'], file['name']);
                                }
                              },
                              child: ListTile(
                                leading: Stack(
                                  children: [
                                    Image.network(
                                      file['thumbnail'], 
                                      width: 40,
                                      height: 40, 
                                      fit: BoxFit.cover,
                                      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                                        // Get the appropriate icon based on the file type
                                        return getFileIcon(file['name']);
                                      },
                                    ),
                                    if (isSelected)
                                      Positioned.fill(
                                        child: Container(
                                          color: Colors.blue.withOpacity(0.5),
                                          child: Icon(Icons.check, color: Colors.white, size: 40),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text(file['name']),
                                trailing: IconButton(
                                  icon: Icon(
                                    selectionMode
                                        ? (isSelected ? Icons.check_circle : Icons.radio_button_unchecked)
                                        : Icons.more_vert,
                                    color: isSelected ? Colors.blue : null,
                                  ),
                                  onPressed: selectionMode
                                      ? () => toggleSelectionMode(file)
                                      : () => _showOptions(context, file),
                                ),
                              ),
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
                if (totalItems > itemsPerPage && itemsPerPage > 0) ...[
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue, // Set background color to blue
                        ), // Disable button while uploading
                        child: Text(
                          "Previous",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => showGoToPageDialog(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue, // Set background color to blue
                        ), // Disable button while uploading
                        child: Text(
                          "Page ${currentPage + 1} of ${(totalItems / itemsPerPage).ceil()}",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: (currentPage + 1) * itemsPerPage < totalItems
                            ? () {
                                setState(() {
                                  currentPage++;
                                });
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue, // Set background color to blue
                        ), // Disable button while uploading
                        child: Text(
                          "Next",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                ],
              ],
            ),
    );
  
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
          },
          onMove: () {
            Navigator.pop(context);
            _copyFile(item, 2);            
          },
          onDownload: () async {
            final scaffoldMessenger = ScaffoldMessenger.of(context); // Store reference
            Navigator.of(context, rootNavigator: true).pop(); // Close the modal
            setState(() {
              isLoading = true;
            });
            String subpath = visitedFolderIDs
              .map((entry) => entry[1])
              .where((path) => path.isNotEmpty)
              .join('/');
            if (item != "") {
              if (item.containsKey('file_code')) {
                mainFeature.adddownloadingQueue([{
                  "fileCode": item['file_code'], 
                  "fileName": item['name'], 
                  "filePath": subpath
                }]);
              } else {
                await mainFeature.downloadFolder(item['fld_id'], item['name'], subpath);
              }
            } else {
              for (dynamic selectedItem in selectedItems) {
                if (selectedItem.containsKey('file_code')) {
                  mainFeature.adddownloadingQueue([{
                    "fileCode": selectedItem['file_code'], 
                    "fileName": selectedItem['name'], 
                    "filePath": subpath
                  }]);
                } else {
                  await mainFeature.downloadFolder(selectedItem['fld_id'], selectedItem['name'], subpath);
                }
              }
            }
            String downloadPath = await getDownloadDirectory();
            setState(() {
              selectedItems = [];
              isLoading = false;
            });
            downloadPath = downloadPath.replaceAll("/storage/emulated/0", "");
            scaffoldMessenger.showSnackBar(
              SnackBar(content: Text('File/Folder(s) are downloaded to $downloadPath'), duration: Duration(seconds: 10),),
            );
          },
          onRemove: () async {
            Navigator.pop(context);
            setState(() {
              isLoading = true;
            });
            if (item != "") {
              await mainFeature._removeFile(item);
            } else {
              for (dynamic selectedItem in selectedItems) {
                await mainFeature._removeFile(selectedItem);
              }
            }
            setState(() {
              selectedItems = [];
              isLoading = false;
            });
            _fetchFilesAndFolders(visitedFolderIDs.last.first.toString());
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
      setState(() {
        isLoading = true;
      });
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
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print("Error: $e");
      setState(() {
        isLoading = false;
      });
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
              child: Text(
                "Close",
                style: TextStyle(color: Colors.blue),
              ),
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
              child: Text(
                "Close",
                style: TextStyle(color: Colors.blue),
              ),
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
      barrierDismissible: true, // Makes the dialog dismissable by tapping outside
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
    ).then((value) {
      // Ensure that audio is stopped when dialog is dismissed (by tapping outside)
      audioPlayer.stop();
    });
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
      _fetchFilesAndFolders(0);
      visitedFolderIDs = [[0, '/'], [0, '/']];
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
    print("filePath: $filePath");
    
    // Get the download directory if no path is provided
    if (filePath == "") saveDirectory = await getDownloadDirectory();
    print("saveDirectory: $saveDirectory");
    
    try {
      String downloadLink = await _getDownloadLink(fileCode);
      if (Platform.isAndroid) {
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          print("Storage permission denied");
          return;
        }
      }
      final response = await http.get(Uri.parse(downloadLink));
      if (response.statusCode == 200) {
        String filePath = '$saveDirectory/$fileName';
        File file = File(filePath);
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }
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
        await downloadFolder(folder['fld_id'], folder['name'], saveDirectory);
      }
    }
    if (fileFolders.containsKey('files')) {
      dynamic files = fileFolders['files'];
      for (dynamic file in files) {
        await downloadFile(file['file_code'], file['name'], saveDirectory);
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
            decoration: InputDecoration(
              hintText: 'Enter new name',
              labelStyle: TextStyle(color: Colors.blue), // Change label color
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2.0), // Border when focused
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                setState(() {
                  isLoading = true;
                });
                await mainFeature._renameFile(item, controller.text);
                await _fetchFilesAndFolders(visitedFolderIDs.last.first);
                setState(() {
                  isLoading = false; // Start loading
                });
              },
              child: Text('Rename', style: TextStyle(color: Colors.blue),),
            ),
          ],
        );
      },
    );
  }

  void _copyFile(dynamic item, int copyOrMove) {
    copyStatus = copyOrMove;
    if (item != ""){
      copiedFileFolders = [item];
    } else {
      copiedFileFolders = selectedItems;
      setState(() {
        selectedItems = [];
      });
    }
  }

  void _pasteFile() async {
    setState(() {
      isLoading = true; // Start loading
    });
    print("paste file.");
    String folderID = visitedFolderIDs.last.first.toString();
    for(dynamic copiedFileFolder in copiedFileFolders){
      if (copyStatus == 1 && copiedFileFolder.containsKey('file_code')) {  // copy file.
        print("copy file.");
        String fileCode = copiedFileFolder['file_code'];
        final response = await http.get(
          Uri.parse('$baseURL/file/clone?file_code=$fileCode&sess_id=${mainFeature.sessionId}'),
        );

        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          String clonedFileCode = data['result']['filecode'];
          final response1 = await http.get(
            Uri.parse('$baseURL/file/set_folder?file_code=$clonedFileCode&fld_id=$folderID&sess_id=${mainFeature.sessionId}'),
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
      } else if (copyStatus == 2 && copiedFileFolder.containsKey('file_code')) { // move file.
        print("move file.");
        String fileCode = copiedFileFolder['file_code'];
          final response = await http.get(
            Uri.parse('$baseURL/file/set_folder?file_code=$fileCode&fld_id=$folderID&sess_id=${mainFeature.sessionId}'),
          );
          if (response.statusCode == 200) {
            print('Successfully moved.');
          } else {
            print("Failed to paste file.");
          }
      } else if (copyStatus == 1 && !copiedFileFolder.containsKey('file_code')) { // copy folder.
        print("copy folder.");
        String copyFolderID = copiedFileFolder['fld_id'].toString();
        final response = await http.get(
          Uri.parse('$baseURL/folder/copy?fld_id=$copyFolderID&sess_id=${mainFeature.sessionId}'),
        );

        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          String clonedFolderID = data['result']['fld_id'].toString();
          final response1 = await http.get(
            Uri.parse('$baseURL/folder/move?fld_id=$clonedFolderID&dest_fld_id=$folderID&sess_id=${mainFeature.sessionId}'),
          );
          if (response1.statusCode == 200) {
            String copiedFolderID = jsonDecode(response.body)['result']['fld_id'].toString();
            mainFeature._renameFile(jsonDecode(response.body)['result'], copiedFileFolder['name']);
            print('Successfully copied.');
          } else {
            print("Failed to paste folder, it's cloned to the root directory.");
          }
        }
      } else if (copyStatus == 2 && !copiedFileFolder.containsKey('file_code')) { // move folder.
        print("move folder.");
        String moveFolderID = copiedFileFolder['fld_id'].toString();
        final response1 = await http.get(
          Uri.parse('$baseURL/folder/move?fld_id=$moveFolderID&dest_fld_id=$folderID&sess_id=${mainFeature.sessionId}'),
        );
        if (response1.statusCode == 200) {
          print('Successfully moved.');
        } else {
          print("Failed to move.");
        }
      } else {
        print('Nothing to paste.');
      }
    }
    copyStatus = 0;
    copiedFileFolders = [];
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
      Uri.parse('$baseURL/folder/list?fld_id=${fldId.toString()}&sess_id=${mainFeature.sessionId}'),
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
                leading: Icon(Icons.wifi, color: Colors.blue),
                title: Text("Only Sync Over Wi-Fi"),
                trailing: Switch(
                  value: _onlyWifiSync,
                  activeColor: Colors.blue, // Set the active color to blue
                  onChanged: (val) {
                    _toggleWifiSync(val);
                    Navigator.pop(context);
                  },
                ),
              ),
              ListTile(
                leading: Icon(Icons.backup, color: Colors.blue),
                title: Text("Auto Camera Roll Backup"),
                trailing: Switch(
                  value: _autoCameraBackup,
                  activeColor: Colors.blue, // Set the active color to blue
                  onChanged: (val) {
                    setState(() => _autoCameraBackup = val);
                    Navigator.pop(context);
                    _toggleCameraBackup(val);
                  },
                ),
              ),

              // Security Options
              ListTile(
                leading: Icon(Icons.lock, color: Colors.blue),
                title: Text("App Lock"),
                onTap: () => _enableAppLock(context),
              ),

              ListTile(
                leading: Icon(Icons.pageview, color: Colors.blue),
                title: Text("Set Number Of Images Per Page"),
                onTap: _showSetNumberOfImagesPerPage,
              ),

              // About & Legal
              ListTile(
                leading: Icon(Icons.info, color: Colors.blue),
                title: Text("About Us"),
                onTap: () => _openURL("https://filelu.com"),
              ),
              ListTile(
                leading: Icon(Icons.article, color: Colors.blue),
                title: Text("Terms"),
                onTap: () => _openURL("https://filelu.com/pages/terms/"),
              ),
              ListTile(
                leading: Icon(Icons.privacy_tip, color: Colors.blue),
                title: Text("Privacy Policy"),
                onTap: () => _openURL("https://filelu.com/pages/privacy-policy/"),
              ),

              // Logout
              ListTile(
                leading: Icon(Icons.logout, color: Colors.blue),
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
                setState(() {
                  fromToday = true;
                });
                _startBackup();
                Navigator.pop(context);
              },
              child: Text("Today Only", style: TextStyle(color: Colors.blue)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  fromToday = false;
                });
                _startBackup();
                Navigator.pop(context);
              },
              child: Text("From Beginning", style: TextStyle(color: Colors.blue)),
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
                  labelStyle: TextStyle(color: Colors.blue), // Change label color
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue, width: 2.0), // Border when focused
                  ),
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
              child: Text("Set", style: TextStyle(color: Colors.blue),),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: Text("Cancel", style: TextStyle(color: Colors.blue),),
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
    if (prefs.getBool('autoCameraBackup') == true) {
      _startBackup();
    }
    if (prefs.getString('last_backup_date') != "") {
      print("last_backup_date: ${prefs.getString('last_backup_date')}");
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();

    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is List<String>) {
      await prefs.setStringList(key, value);
    } else if (value is DateTime) {
      await prefs.setString(key, value.toString());
    } else {
      throw ArgumentError("Unsupported type for SharedPreferences");
    }
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
    } else {
      _stopBackgroundSync();
    }
  }

  void _openURL(String url) async {
    Uri uri = Uri.parse(url);

    if (Platform.isWindows) {
      // Use `Process.start` on Windows instead of `launchUrl`
      await Process.start('explorer.exe', [url]);
    } else {
      // setState(() {
      //   errorMessage += "NotWin...";
      // });
      if (await canLaunchUrl(uri)) {
        // setState(() {
        //   errorMessage += "Can Launch Url...";
        // });
        await launchUrl(uri, mode: LaunchMode.inAppWebView);
      } else {
        // setState(() {
        //   errorMessage += "❌ Could not open: $url...";
        // });
        print("❌ Could not open: $url");
      }
    }
  }

  Future<void> _enableAppLock(BuildContext context) async {
    String? password = await _getSavedPassword();

    if (password == null || password == "") {
      // Prompt user to set a new password
      String? newPassword = await _showPasswordDialog(context, "Set Password");
      if (newPassword != null) {
        String? confirmPassword = await _showPasswordDialog(context, "Retype Password");
        
        if (confirmPassword == newPassword) {
          await _saveSetting('appLockPassword', newPassword);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("App Lock Enabled Successfully"), duration: Duration(seconds: 3)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Passwords do not match. Try again."), duration: Duration(seconds: 3)),
          );
        }
      }
    } else {
      String? enteredPassword = await _showPasswordDialog(context, "Enter Password to Unlock");
      if (enteredPassword == password) {
        await _saveSetting('appLockPassword', "");
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Incorrect Password"), duration: Duration(seconds: 3)),
        );
      }
    }
  }

  Future<String?> _showPasswordDialog(BuildContext context, String title) async {
    TextEditingController passwordController = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: "Enter Password",
              labelStyle: TextStyle(color: Colors.blue), // Change label color
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2.0), // Border when focused
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                "Cancel",
                style: TextStyle(color: Colors.blue),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, passwordController.text),
              child: Text(
                "OK",
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _getSavedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('appLockPassword');
  }

  void _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('sessionId', "");
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => LoginPage()),
      (Route<dynamic> route) => false, // Removes all previous routes
    );
  }

  void _startBackup() async {
    MainFeature uploader = MainFeature();
    String cameraFolderID = await uploader.getFolderID("Camera", "0");
      if (cameraFolderID == "") {
        cameraFolderID = await uploader.createCloudFolder("Camera", "0");
      }
    _uploadCameraFolder(cameraFolderID);
    if (_backgroundIsolate != null) return;
    ReceivePort newReceivePort = ReceivePort();
    _backgroundIsolate = await Isolate.spawn(_fileWatcher, newReceivePort.sendPort);
    newReceivePort.listen((message) async {
      String detectedFilePath = message as String;
      print("📂 New file detected in main isolate: $detectedFilePath");
      await Future.delayed(Duration(seconds: 3));
      await uploader.uploadFile(detectedFilePath, cameraFolderID);
    });

    print("✅ Background Sync Started!");
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Android storage permission
      if (await Permission.storage.request().isGranted) {
        return true;
      }
      if (await Permission.manageExternalStorage.request().isGranted) {
        return true;
      }
    } else if (Platform.isIOS) {
      // iOS photo library permission
      if (await Permission.photos.request().isGranted) {
        return true;
      }
    }
    return false;
  }

  Future<void> _uploadCameraFolder(String cameraFolderID) async {
    bool hasPermission = await _requestStoragePermission();
    if (!hasPermission) {
      print("❌ Storage permission denied");
      return;
    }
    List<String> cloudFiles = [];
    final response = await http.get(
      Uri.parse('$baseURL/folder/list?fld_id=$cameraFolderID&sess_id=${mainFeature.sessionId}'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
    }

    List<FileSystemEntity> mediaFiles = [];

    if (Platform.isAndroid) {
      // For Android: Accessing the DCIM/Camera folder
      const String directoryPath = "/storage/emulated/0/DCIM/Camera";
      final directory = Directory(directoryPath);
      if (directory.existsSync()) {
        mediaFiles = directory.listSync().where(
          (file) {
            if (file is File) {
              final ext = file.path.split('.').last.toLowerCase();
              return ["jpg", "jpeg", "png", "mp4", "mov"].contains(ext);
            }
            return false;
          },
        ).toList();
      }
    } else if (Platform.isIOS) {
    }

    if (fromToday) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      mediaFiles = mediaFiles.where((file) {
        return FileStat.statSync(file.path).modified.isAfter(DateTime.parse(today));
      }).toList();
    }

    for (var file in mediaFiles) {
      if (!cloudFiles.contains(file.path.split('/').last.split(r'\').last)) {
        MainFeature uploader = MainFeature();
        String cameraFolderID = await uploader.getFolderID("Camera", "0");
        if (cameraFolderID == "") {
          cameraFolderID = await uploader.createCloudFolder("Camera", "0");
        }
        await uploader.uploadFile(file.path, cameraFolderID);
        lastBackupDate = DateTime.now();
        _saveSetting("last_backup_date", lastBackupDate);
      }
    }
    print("Backup completed: ${mediaFiles.length} files uploaded");
  }

  void _stopBackgroundSync() {
    _backgroundIsolate?.kill(priority: Isolate.immediate);
    _backgroundIsolate = null;
    print("❌ Background Sync Stopped.");
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
    return _buildFileFolderList();
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
        if (item != "")
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
  final MainFeature mainFeature;
  SyncPage({required this.mainFeature});

  @override
  _SyncPageState createState() => _SyncPageState(mainFeature: mainFeature);
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
  final MainFeature mainFeature;
  bool isLoading = false;
  Isolate? _backgroundIsolate;
  bool isSyncing = false;

  _SyncPageState({required this.mainFeature});

  @override
  void initState() {
    super.initState();
    _loadSyncOrders(); 
    _initializeServerUrl();
    _runPerformSync();
    _watchFileCDM();
  }

  Future<void> _watchFileCDM() async {
    if (_backgroundIsolate != null) return;

    ReceivePort newReceivePort = ReceivePort();
    _backgroundIsolate = await Isolate.spawn(_filefolderWatcher, newReceivePort.sendPort);

    newReceivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        String eventType = message['event']; // "create", "delete", "modify", "move"
        String detectedFilePath = message['path'];

        // Optional delay before handling the event
        await Future.delayed(Duration(seconds: 3));

        // Handle file/folder event based on type
        switch (eventType) {
          case 'create':
            print("📥 File Created: $detectedFilePath");
            // TODO: Upload file or perform necessary actions
            break;
          case 'delete':
            print("🗑️ File Deleted: $detectedFilePath");
            // TODO: Handle file deletion
            break;
          case 'modify':
            print("✏️ File Modified: $detectedFilePath");
            // TODO: Handle file modification
            break;
          case 'move':
            print("🔄 File Moved: $detectedFilePath");
            // TODO: Handle file move
            break;
          default:
            print("⚠️ Unknown event detected: $eventType");
        }
      }
    });
  }

  Future<void> _runPerformSync() async {
    if (!isSyncing) {
      isSyncing = true;
      try {
        for (int index = 0; index < syncOrders.length; index++) {
          if (syncOrders[index].isRunning) {
            await _performSync(syncOrders[index]);
          }
        }
      } catch (e) {
        print("Error during sync: $e");
      } finally {
        isSyncing = false;
      }
    }

    await Future.delayed(Duration(seconds: 20));
    _runPerformSync();
  }

  Future<void> _initializeServerUrl() async {
    try {
      final response = await http.get(
        Uri.parse('$baseURL/upload/server?sess_id=${mainFeature.sessionId}'),
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
              content: SingleChildScrollView( // Fix overflow issue
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Folder path input
                    TextField(
                      controller: folderController,
                      decoration: InputDecoration(
                        labelText: "Local Folder Path",
                        labelStyle: TextStyle(color: Colors.blue), // Change label color
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue, width: 2.0), // Border when focused
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.folder, color: Colors.blue),
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
                      decoration: InputDecoration(
                        labelText: "Remote Folder",
                        labelStyle: TextStyle(color: Colors.blue), // Change label color
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue, width: 2.0), // Border when focused
                        ),
                      ),
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
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _addSyncOrder(folderController.text, selectedType, remotePath);
                    Navigator.pop(context);
                  },
                  child: Text(
                    "Add",
                    style: TextStyle(color: Colors.blue)
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: Colors.blue)
                  ),
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
    print(order.syncType);
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
      Uri.parse('$baseURL/folder/list?fld_id=$folderID&sess_id=${mainFeature.sessionId}'),
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
          MainFeature uploader = MainFeature();
          await uploader.uploadFile(filePath, folderID);
        }
      }
    }

    for (String localFolder in localFolders) {
      if (!cloudFolders.contains(localFolder)) {
        String newFoldeId = await createCloudFolder(localFolder, folderID);
        await _uploadFiles("$localPath/$localFolder", newFoldeId);
      } else {
        await _uploadFiles("$localPath/$localFolder", cloudFolderCodes[cloudFolders.indexOf(localFolder)]);
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
      Uri.parse('$baseURL/folder/list?fld_id=$folderID&sess_id=${mainFeature.sessionId}'),
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
      await createFolderIfNotExists("$localPath${Platform.pathSeparator}$cloudFolder");
      await _downloadFiles("$localPath${Platform.pathSeparator}$cloudFolder", cloudFolderCode);
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
      Uri.parse('$baseURL/folder/list?fld_id=$folderID&sess_id=${mainFeature.sessionId}'),
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
          MainFeature uploader = MainFeature();
          await uploader.uploadFile(filePath, folderID);
        }
      }
    }

    for (int i = 0; i < cloudFiles.length; i++) {
      String file = cloudFiles[i];
      if (!localFiles.contains(file)) {
        await http.get(Uri.parse('$baseURL/file/remove?file_code=${cloudFileCodes[i]}&remove=1&sess_id=${mainFeature.sessionId}'));
        print("Deleted from cloud: $file");
      }
    }

    for (String localFolder in localFolders) {
      if (!cloudFolders.contains(localFolder)) {
        String newFoldeId = await createCloudFolder(localFolder, folderID);
        await _onewaySync("$localPath/$localFolder", newFoldeId);
      } else {
        await _onewaySync("$localPath/$localFolder", cloudFolderCodes[cloudFolders.indexOf(localFolder)]);
      }
    }

  }

  Future<void> _twowaySync(String localPath, String folderID, dynamic folderData) async {
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
      await _uploadFiles(localPath, folderID);
      await _downloadFiles(localPath, folderID);
      return;
    }

    if (!folderData.containsKey('file') && !folderData.containsKey('folder')) {
      await _uploadFiles(localPath, folderID);
      await _downloadFiles(localPath, folderID);
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
      Uri.parse('$baseURL/folder/list?fld_id=$folderID&sess_id=${mainFeature.sessionId}'),
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
          MainFeature uploader = MainFeature();
          await uploader.uploadFile(filePath, folderID);
        }
      }
    }

    for (int i = 0; i < syncFiles.length; i ++) {
      String file = syncFiles[i];
      if(!localFiles.contains(file)) {
        String fileToDeleteCode = syncFileCodes[i];
        await http.get(Uri.parse('$baseURL/file/remove?file_code=$fileToDeleteCode&remove=1&sess_id=${mainFeature.sessionId}'));
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
      Uri.parse('$baseURL/folder/list?fld_id=$fldID&sess_id=${mainFeature.sessionId}'),
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
      Uri.parse('$baseURL/folder/delete?fld_id=$folderID&sess_id=${mainFeature.sessionId}'),
    );
    if (response.statusCode == 200) {
      print("Successfully delete cloud folder $folderID.");
    }
  }

  Future<String> _getDownloadLink(String fileCode) async {
    final response = await http.get(
      Uri.parse('$baseURL/file/direct_link?file_code=$fileCode&sess_id=${mainFeature.sessionId}'),
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['result']['url'];
    }
    return "";
  }

  Future<String> getFolderID(String folderName, String parentFolderID) async {
    final response = await http.get(
      Uri.parse('$baseURL/folder/list?fld_id=$parentFolderID&sess_id=${mainFeature.sessionId}'),
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
    final response1 = await http.get(
      Uri.parse('$baseURL/folder/create?parent_id=$parentFolderID&name=$folderName&sess_id=${mainFeature.sessionId}'),
    );
    if (response1.statusCode == 200) {
      var data = jsonDecode(response1.body);
      return data['result']['fld_id'].toString();
    }
    return "";
  }

  Future<String> createCloudFolder(String localFolder, String parentId) async {
    print(localFolder);
    final response = await http.get(
      Uri.parse('$baseURL/folder/create?parent_id=$parentId&name=$localFolder&sess_id=${mainFeature.sessionId}')
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
    List<String> paths = path.split('/');
    if (path.length > 1) {
      path = "${paths[paths.length - 2]}/${paths.last}";
    }
    path = path.replaceAll("File Provider Storage", "");
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('Sync Files & Folders')
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSyncOrderDialog,
        backgroundColor: Colors.blue,
        child: Icon(Icons.add, color: Colors.white),
      ),
      body: isLoading
            ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)),) // Show loading indicator
            : Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: syncOrders.length,
              itemBuilder: (context, index) {
                final order = syncOrders[index];
                return Container(
                  margin: EdgeInsets.symmetric(vertical: 8.0), // Space between items
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey, width: 1), // Border color and width
                    borderRadius: BorderRadius.circular(8.0), // Rounded corners
                    color: Colors.white, // Background color
                  ),
                  child: ListTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Sync Icon
                        Icon(
                          order.syncType == "Upload Only" ? Icons.upload : 
                          order.syncType == "Download Only" ? Icons.download : 
                          order.syncType == "One-Way Sync" ? Icons.arrow_forward_ios : 
                          order.syncType == "Two-Way Sync" ? Icons.sync : 
                          Icons.info, // Default icon if neither condition matches
                          color: Colors.blue,
                        ),
                        // Column for Remote and Local Paths
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.remotePath,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              abbreviate(order.localPath),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                        SizedBox(width: 10), // Space between sections
                        // Column for Action Buttons
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Start/Stop Button
                            IconButton(
                              icon: Icon(order.isRunning ? Icons.pause : Icons.play_arrow, color: Colors.blue),
                              onPressed: () => _toggleSync(index),
                            ),
                            // Delete Button
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.black),
                              onPressed: () => _deleteSyncOrder(index),
                            ),
                          ],
                        ),
                      ],
                    ),
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
  final MainFeature mainFeature;
  UploadPage({required this.mainFeature});

  @override
  _UploadPageState createState() => _UploadPageState(mainFeature: mainFeature);
}

class _UploadPageState extends State<UploadPage> {
  String uploadServer = "";
  final MainFeature mainFeature;
  bool isLoading = false;
  List<String> selectedFiles = [];
  double uploadProgress = 0.0; // Track upload progress
  int uploadedItemCounts = 0;

  _UploadPageState({required this.mainFeature});

  @override
  void initState() {
    super.initState();
    _initializeServerUrl();
    timer();
  }

  Future<void> _initializeServerUrl() async {
    try {
      final response = await http.get(
        Uri.parse('$baseURL/upload/server?sess_id=${mainFeature.sessionId}'),
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
    if (selectedFiles.isEmpty) return;
    setState(() {
      isLoading = true;
      uploadProgress = 0.0;
    });
    MainFeature uploader = MainFeature();
    for (int i = 0; i< selectedFiles.length; i ++) {
      String filePath = selectedFiles[i];
      print("File $filePath is uploading now...");
      await uploader.uploadFile(filePath, "0");
      print("File $filePath is uploaded.");
      uploadedItemCounts ++;
    }
    setState(() {
      selectedFiles = [];
      isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Files uploaded successfully!")),
    );
  }

  Future<void> timer() async {
    if (selectedFiles.isNotEmpty && isLoading == true) {
      setState(() {
        uploadProgress = min(uploadProgress + 0.005, (uploadedItemCounts + 1) / selectedFiles.length - 0.05);
        uploadProgress = max(uploadProgress, uploadedItemCounts / selectedFiles.length);
      });
    }
    await Future.delayed(Duration(milliseconds: 50)); // Simulated delay
    timer();
  }
  
  Future<String> getFolderID(String folderName, String parentFolderID) async {
    final response = await http.get(
      Uri.parse('$baseURL/folder/list?fld_id=$parentFolderID&sess_id=${mainFeature.sessionId}'),
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
    await http.get(Uri.parse('$baseURL/file/set_folder?file_code=$fileCode&fld_id=$folderID&sess_id=${mainFeature.sessionId}'));
  }

  Future<String> createCloudFolder(String localFolder, String parentId) async {
    final response = await http.get(
      Uri.parse('$baseURL/folder/create?parent_id=$parentId&name=$localFolder&sess_id=${mainFeature.sessionId}')
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('Upload Files')
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _pickFiles,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, // Set background color to blue
              ), // Disable button while uploading
              child: Text(
                'Select Files',
                style: TextStyle(color: Colors.white),
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: selectedFiles.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(selectedFiles[index].split(r'\').last.split('/').last),
                  );
                },
              ),
            ),
            if (isLoading) // Show progress bar when uploading
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: LinearProgressIndicator(value: uploadProgress, color: Colors.blue,),
              ),
            ElevatedButton(
              onPressed: isLoading ? null : uploadFiles,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, // Set background color to blue
              ), // Disable button while uploading
              child: Text(
                'Upload Files',
                style: TextStyle(color: Colors.white), // Set text color to white
              ),
            ),
          ],
        ),
      ),
    );
  }

}

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
            : CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying ? _controller.pause() : _controller.play();
          });
        },
        child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.blue),
      ),
    );
  }
}

class MainFeature {
  String sessionId = "";
  List<dynamic> uploadQueue = [];
  List<dynamic> downloadQueue = [];
  String serverUrl = "";
  bool isFirstCall = true;
  int currentUploadingItemIndex = 0;
  int currentDownloadingItemIndex = 0;

  Future<void> initState() async {
    if (isFirstCall) {
      await getSessionId();
      await _initializeServerUrl();
      _infinitCycling();
    }
    isFirstCall = false;
  }

  Future<void> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    sessionId = prefs.getString('sessionId')!;
  }

  void addUploadQueue(List<dynamic> uploadingItems) {
    uploadQueue.addAll(uploadingItems);
  }

  void adddownloadingQueue(List<dynamic> downloadingItems){
    downloadQueue.addAll(downloadingItems);
  }

  Future<void> _infinitCycling() async {
    for(int i = 0; i < 10; i ++) {
      if (uploadQueue.isNotEmpty && uploadQueue.length > currentUploadingItemIndex) {
        String fileCode = await uploadFile(uploadQueue[currentUploadingItemIndex]['filePath'], uploadQueue[currentUploadingItemIndex]['folderID']);
        uploadQueue[currentUploadingItemIndex]['fileCode'] = fileCode;
        currentUploadingItemIndex ++;
      }
      if (downloadQueue.isNotEmpty && downloadQueue.length > currentDownloadingItemIndex) {
        await downloadFile(downloadQueue[currentDownloadingItemIndex]['fileCode'], 
                          downloadQueue[currentDownloadingItemIndex]['fileName'],
                          downloadQueue[currentDownloadingItemIndex]['filePath']);
        currentDownloadingItemIndex ++;
      }
    }
    await Future.delayed(Duration(seconds: 10));
    await _infinitCycling();
  }

  Future<void> _initializeServerUrl() async {
    try {
      final response = await http.get(
        Uri.parse('$baseURL/upload/server?sess_id=$sessionId'),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        serverUrl = data['result'];
        print("Upload server initialized: $serverUrl");
      } else {
        print("Failed to get upload server: ${response.reasonPhrase}");
      }
    } catch (e) {
      print("Error fetching upload server: $e");
    }
  }

  Future<String> uploadFile(String filePath, String folderID) async {
    print('trying to upload: $filePath');
    if (serverUrl == null) {
      print("No available upload server. Upload failed.");
      return "";
    }
    // Check if the file exists
    File file = File(filePath);
    if (!await file.exists()) {
      print("File does not exist: $filePath");
      return "";
    }
    int fileSize = await file.length();
    print("Uploading file of size: $fileSize bytes");

    // Check if the file already exists on cloud
    List<String> cloudFiles = [];
    final response = await http.get(
      Uri.parse('$baseURL/folder/list?fld_id=$folderID&sess_id=$sessionId'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
    }
    if(cloudFiles.contains(filePath.split('/').last.split(r'\').last)) return "";

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
        await moveFile(responseData[0]['file_code'], folderID);
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
    await http.get(Uri.parse('$baseURL/file/set_folder?file_code=$fileCode&fld_id=$folderID&sess_id=$sessionId'));
  }

  Future<String> getFolderID(String folderName, String parentFolderID) async {
    final response = await http.get(
      Uri.parse('$baseURL/folder/list?fld_id=$parentFolderID&sess_id=$sessionId'),
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
      Uri.parse('$baseURL/folder/create?parent_id=$parentId&name=$localFolder&sess_id=$sessionId')
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['result']['fld_id'].toString();
    }
    return "";
  }

  Future<String> getDownloadDirectory() async {
    String subpath = "";
    subpath = subpath.replaceAll(RegExp(r'/{2,}'), '/');
    if (subpath.endsWith('/')) {
      subpath = subpath.substring(0, subpath.length - 1);
    }
    if (Platform.isAndroid) {
      String path = '/storage/emulated/0/Download/FileLuSync/$subpath';
      return path;
    } else if (Platform.isIOS) {
      Directory dir = await getApplicationDocumentsDirectory();
      return "${dir.path}/$subpath"; // Add subpath here
    } else if (Platform.isWindows) {
      String? userHome = Platform.environment['USERPROFILE'];
      return "$userHome\\Documents\\MySyncFolder\\$subpath";
    } else if (Platform.isMacOS) {
      Directory dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      return "${dir.path}/$subpath"; // Add subpath here if needed
    } else if (Platform.isLinux) {
      String? home = Platform.environment['HOME'];
      return "$home/Downloads/$subpath"; // Add subpath here if needed
    } else {
      throw Exception("Unsupported platform");
    }
  }

  Future<String> _getDownloadLink(fileCode) async {
    final response = await http.get(
      Uri.parse('$baseURL/file/direct_link?file_code=$fileCode&sess_id=$sessionId')
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      Uri.parse(data['result']['url']);
      return data['result']['url'];
    } else {
      return "cannot get download link";
    }
  }

  Future<void> downloadFile(String fileCode, String fileName, String filePath) async {
    String parentDirectory = await getDownloadDirectory();
    String saveDirectory = "$parentDirectory/$filePath";
    print("saveDirectory: $saveDirectory");
    
    try {
      String downloadLink = await _getDownloadLink(fileCode);
      if (Platform.isAndroid) {
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          print("Storage permission denied");
          return;
        }
      }
      final response = await http.get(Uri.parse(downloadLink));
      if (response.statusCode == 200) {
        String filePath = '$saveDirectory/$fileName';
        File file = File(filePath);
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }
        await file.writeAsBytes(response.bodyBytes);
        print("Download complete! File saved at: $filePath");
      } else {
        print("Download failed. Server response: ${response.statusCode}");
      }
    } catch (e) {
      print("Error downloading file: $e");
    }
  }

  Future<void> downloadFolder(int folderID, String folderName, String subpath) async {
    String saveDirectory= "$subpath/$folderName";
    await createFolderIfNotExists(saveDirectory);
    dynamic fileFolders = await fetchFilesAndFolders(folderID);
    if (fileFolders.containsKey('folders')) {
      dynamic folders = fileFolders['folders'];
      for (dynamic folder in folders) {
        await downloadFolder(folder['fld_id'], folder['name'], saveDirectory);
      }
    }
    if (fileFolders.containsKey('files')) {
      dynamic files = fileFolders['files'];
      for (dynamic file in files) {
        adddownloadingQueue([{
          "fileCode": file['file_code'], 
          "fileName": file['name'], 
          "filePath": saveDirectory
        }]);
      }
    }
  }
  
  Future<void> createFolderIfNotExists(String path) async {
    String parentDirectory = await getDownloadDirectory();
    final directory = Directory("$parentDirectory/$path");

    // Check if the directory exists
    if (await directory.exists()) {
      print('Directory already exists: $path');
    } else {
      // Create the directory
      await directory.create(recursive: true);
      print('Directory created: $path');
    }
  }

  Future<dynamic> fetchFilesAndFolders(fldId) async {
    final response = await http.get(
      Uri.parse('$baseURL/folder/list?fld_id=${fldId.toString()}&sess_id=$sessionId'),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data['result'];
    } else {
      print('Failed to load folders and files');
      return [];
    }
  }

  Future<void> _removeFile(dynamic item) async {
    print(item);
    if(item.containsKey('file_code')) {
      String fileCode = item['file_code'].toString();
      final response = await http.get(
        Uri.parse('$baseURL/file/remove?file_code=$fileCode&remove=1&sess_id=$sessionId'),
      );
      if (response.statusCode == 200) {
        print('Successfully removed.');
      } else {
        print("Failed to remove.");
      }
    } else {
      String folderID = item['fld_id'].toString();
      final response = await http.get(
        Uri.parse('$baseURL/folder/delete?fld_id=$folderID&sess_id=$sessionId'),
      );
      if (response.statusCode == 200) {
        print('Successfully removed.');
      } else {
        print("Failed to remove.");
      }
    }
  }

  Future<void> _renameFile(dynamic item, String newName) async {
    final response;
    if (item.containsKey('file_code')) {
      String fileCode = item['file_code'].toString();
      response = await http.get(
        Uri.parse('$baseURL/file/rename?file_code=$fileCode&name=$newName&sess_id=$sessionId'),
      );
    } else if (item.containsKey('fld_id')) {
      String folderID = item['fld_id'].toString();
      response = await http.get(
        Uri.parse('$baseURL/folder/rename?fld_id=$folderID&name=$newName&sess_id=$sessionId'),
      );
    } else {
      response = {'statusCode': 404};
    }
    
    if (response.statusCode == 200) {
      print('Successfully rename ${item['name']} to $newName.');
    } else {
      print('Rename ${item.name} failed');
    }
  }

}

void _fileWatcher(SendPort sendPort) async {
  const String directoryPath = "/storage/emulated/0/DCIM/Camera";
  final directory = Directory(directoryPath);

  if (!directory.existsSync()) {
    print("❌ Camera folder not found!");
    return;
  }

  directory.watch(events: FileSystemEvent.create).listen((event) async {
    if (event.type == FileSystemEvent.create) {
      print("📂 New file detected: ${event.path}");
      sendPort.send(event.path); // Send file path to main isolate
    }
  });
}

void _filefolderWatcher(SendPort sendPort) async {
  const String directoryPath = "/storage/emulated/0/";
  final directory = Directory(directoryPath);

  if (!directory.existsSync()) {
    print("❌ Directory not found!");
    return;
  }

  // Function to recursively watch subdirectories
  void watchSubdirectories(Directory dir) {
    try{
      dir.list(recursive: false, followLinks: false).listen((FileSystemEntity entity) {
        if (entity is Directory) {
          if (entity.path.split('/').last == "DCIM1") return;
          if (entity.path.split('/').last == "Android") return;
          // Watch the subdirectory
          entity.watch(events: FileSystemEvent.all).listen((event) {
            if (event.type == FileSystemEvent.create) {
              print("📂 File/Folder Created: ${event.path}");
              sendPort.send({'event': 'create', 'path': event.path});
            } else if (event.type == FileSystemEvent.delete) {
              print("🗑️ File/Folder Deleted: ${event.path}");
              sendPort.send({'event': 'delete', 'path': event.path});
            } else if (event.type == FileSystemEvent.modify) {
              print("✏️ File/Folder Modified: ${event.path}");
              sendPort.send({'event': 'modify', 'path': event.path});
            } else if (event.type == FileSystemEvent.move) {
              print("🔄 File/Folder Moved: ${event.path}");
              sendPort.send({'event': 'move', 'path': event.path});
            }
          });
          watchSubdirectories(entity);
        }
      });
    } catch (e) {
      print('Error while watching subdirectory $dir: $e');
    }
    
  }

  // Watch the main directory
  directory.watch(events: FileSystemEvent.all).listen((event) {
    if (event.type == FileSystemEvent.create) {
      print("📂 File/Folder Created: ${event.path}");
      sendPort.send({'event': 'create', 'path': event.path});
    } else if (event.type == FileSystemEvent.delete) {
      print("🗑️ File/Folder Deleted: ${event.path}");
      sendPort.send({'event': 'delete', 'path': event.path});
    } else if (event.type == FileSystemEvent.modify) {
      print("✏️ File/Folder Modified: ${event.path}");
      sendPort.send({'event': 'modify', 'path': event.path});
    } else if (event.type == FileSystemEvent.move) {
      print("🔄 File/Folder Moved: ${event.path}");
      sendPort.send({'event': 'move', 'path': event.path});
    }
  });

  // Watch the subdirectories
  watchSubdirectories(directory);
}

