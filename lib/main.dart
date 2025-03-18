import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'dart:async';
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

Map<int, http.StreamedResponse?> activeDownloads = {}; // Stores active requests
const String baseURL = "https://filelu.com/app";

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
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: Colors.blue, // Cursor color
          selectionColor: Colors.blue.withOpacity(0.5), // Selection background color
          selectionHandleColor: Colors.blue, // Handle color
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: Colors.blue), // Blue text for all TextButton
        ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: TextStyle(color: Colors.black),  // Customize hint text color
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),  // Blue bottom line on focus
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.grey, width: 1.0),  // Grey bottom line when not focused
          ),
        ),
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
  MainFeature mainFeature = MainFeature();

  @override
  void initState() {
    super.initState();
    mainFeature.onTabChanged = _onItemTapped;
  }

  // Handle navigation between pages
  void _onItemTapped(int index) {
    setState(() {
      mainFeature._tabSelected = index;
    });
  }

  Widget _getPageContent() {
    switch (mainFeature._tabSelected) {
      case 0:
        return MyFilesPage(mainFeature: mainFeature,);
      case 1:
        return SyncPage(mainFeature: mainFeature,);
      case 2:
        return Transfer(mainFeature: mainFeature,);
      case 3:
        return MyAccount(mainFeature: mainFeature,);
      default:
        return OffLine(mainFeature: mainFeature,);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (mainFeature.isOffline) return OffLine(mainFeature: mainFeature);
    return Scaffold(
      body: _getPageContent(),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        currentIndex: mainFeature._tabSelected,
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
            icon: Icon(Icons.sync_alt),
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
  List<dynamic> deletedFiles = [];
  List<dynamic> deletedFolders = [];
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

  final ScrollController _scrollController = ScrollController();
  bool _isPlusButtonVisible = true;
  bool isGridView = false;
  bool isTrashView = true;
  List<String> videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv'];
  List<String> audioExtensions = ['mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a'];
  List<String> photoExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
  List<String> documentExtensions = ['pdf', 'doc', 'docx', 'txt', 'xlsx', 'ppt', 'pptx'];

  _MyFilesPageState({required this.mainFeature});

  @override
  void initState() {
    super.initState();
    _fetchFilesAndFolders(0);
    _loadSettings();
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
      // User is scrolling down, hide the FAB
      if (_isPlusButtonVisible) {
        setState(() {
          _isPlusButtonVisible = false;
        });
      }
    } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
      // User is scrolling up, show the FAB
      if (!_isPlusButtonVisible) {
        setState(() {
          _isPlusButtonVisible = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  // Fetch files and folders using the API
  Future<void> _fetchFilesAndFolders(fldId, {bool hotReload = true}) async {
    if (hotReload == false && mainFeature.cachedFolderInfo.containsKey(fldId.toString())) {
      dynamic data = mainFeature.cachedFolderInfo[fldId.toString()];
      setState(() {
        folders = data['folders'];
        files = data['files'];
      });
    } else {
      setState(() {
        isLoading = true;
        _isPlusButtonVisible = false;
      });
      await mainFeature.initState();
      final response = await mainFeature.getAPICall('$baseURL/folder/list?fld_id=${fldId.toString()}&sess_id=${mainFeature.sessionId}');
      var data = jsonDecode(utf8.decode(response.bodyBytes));
      setState(() {
        folders = data['result']['folders'];
        files = data['result']['files'];
        mainFeature.cachedFolderInfo = {
          ...mainFeature.cachedFolderInfo,
          fldId.toString(): {
            "folders" : folders,
            "files" : files,
          }
        };
      });
      if (deletedFiles.isEmpty && deletedFolders.isEmpty) {
        final response1 = await mainFeature.getAPICall('$baseURL/folder/recycle?sess_id=${mainFeature.sessionId}');
        var data1 = jsonDecode(utf8.decode(response1.bodyBytes));
        setState(() {
          deletedFiles = data1['result']['files'];
          deletedFolders = data1['result']['folders'];
        });
      }
      setState(() {
        isLoading = false;
        _isPlusButtonVisible = true;
      });
    }
  }

  Future<void> _fetchTrash() async {
    setState(() {
      isLoading = true;
      _isPlusButtonVisible = false;
    });
    final response = await mainFeature.getAPICall('$baseURL/folder/recycle?sess_id=${mainFeature.sessionId}');
    var data = jsonDecode(utf8.decode(response.bodyBytes));
    setState(() {
      deletedFiles = data['result']['files'];
      deletedFolders = data['result']['folders'];
    });
    setState(() {
      isLoading = false;
      _isPlusButtonVisible = true;
    });
  }

  Future<String> _getDownloadLink(fileCode) async {
    final response = await mainFeature.getAPICall('$baseURL/file/direct_link?file_code=$fileCode&sess_id=${mainFeature.sessionId}');
    var data = jsonDecode(response.body);
    Uri.parse(data['result']['url']);
    return data['result']['url'];
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

  void performSearch(String query) async {
    setState(() {
      isLoading = true;
      _isPlusButtonVisible = false;
    });
      final response = await http.get(
        Uri.parse('$baseURL/folder/list?search=$query&sess_id=${mainFeature.sessionId}'),
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
      isLoading = false;
      _isPlusButtonVisible = true;
    });
  }

  // Display file/folder list with options
  Widget _buildFileFolderList() {
    int itemsPerPage = numberOfImages; // Number of items per page
    int totalItems = folders.length + files.length;
    bool selectionMode = selectedItems.isNotEmpty; // Enable selection mode if items are selected

    String shortenName(String name, {int maxLength = 10}) {
      if (name.length > maxLength) {
        return '${name.substring(0, maxLength)}...'; // Append ellipsis if truncated
      }
      return name;
    }

    List<dynamic> getPaginatedItems() {
      if (itemsPerPage == 0) {
        if (isTrashView && visitedFolderIDs.last.first == 0) {
          return [
            {
              "name": "Trash",
              "fld_only_me": 0,
              "fld_id": "trash",
              "total_files": deletedFiles.length
            },
            ...folders, 
            ...files
          ];
        } else {
          return [...folders, ...files];
        }
      }
      int startIndex = currentPage * itemsPerPage;
      int endIndex = startIndex + itemsPerPage;
      if (isTrashView && visitedFolderIDs.last.first == 0) {
        return [
          {
            "name": "Trash",
            "fld_only_me": 0,
            "fld_id": "trash",
            "total_files": deletedFiles.length
          },
          ...[...folders, ...files].sublist(
            startIndex,
            endIndex > totalItems ? totalItems : endIndex,
          ),
        ];
      }
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
          return Icon(Icons.image, size: 40, color: Colors.blue);
        case 'mp3':
        case 'wav':
          return Icon(Icons.audiotrack, size: 40, color: Colors.red);
        case 'mp4':
        case 'mov':
          return Icon(Icons.videocam, size: 40, color: Colors.green);
        case 'txt':
          return Icon(Icons.description, size: 40, color: Colors.orange);
        case 'pdf':
          return Icon(Icons.picture_as_pdf, size: 40, color: Colors.purple);
        default:
          return Icon(Icons.insert_drive_file, size: 40, color: Colors.grey); // Default icon for unknown types
      }
    }

    void handleMenuSelection(String selectedOption) async {
      switch(selectedOption) {
        case "grid":
          setState(() {
            isGridView = true;
          });
          break;
        case "list":
          setState(() {
            isGridView = false;
          });
          break;
        case "name":
          setState(() {
            folders.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
            files.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
          });
          break;
        case "date":
          setState(() {
            folders.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
            files.sort((a, b) => a['uploaded'].toString().toLowerCase().compareTo(b['uploaded'].toString().toLowerCase()));
          });
          break;
        case "size":
          setState(() {
            folders.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
            files.sort((a, b) => a['uploaded'].toString().toLowerCase().compareTo(b['uploaded'].toString().toLowerCase()));
          });
          break;
        case "video":
          await _fetchFilesAndFolders(visitedFolderIDs.last.first);
          setState(() {
            folders.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
            files = files.where((file) {
              String extension = file['name'].toString().split('.').last.toLowerCase();
              return videoExtensions.contains(extension);
            }).toList();
          });
          break;
        case "audio":
          await _fetchFilesAndFolders(visitedFolderIDs.last.first);
          setState(() {
            folders.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
            files = files.where((file) {
              String extension = file['name'].toString().split('.').last.toLowerCase();
              return audioExtensions.contains(extension);
            }).toList();
          });
          break;
        case "photo":
          await _fetchFilesAndFolders(visitedFolderIDs.last.first);
          setState(() {
            folders.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
            files = files.where((file) {
              String extension = file['name'].toString().split('.').last.toLowerCase();
              return photoExtensions.contains(extension);
            }).toList();
          });
          break;
        case "document":
          await _fetchFilesAndFolders(visitedFolderIDs.last.first);
          setState(() {
            folders.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
            files = files.where((file) {
              String extension = file['name'].toString().split('.').last.toLowerCase();
              return documentExtensions.contains(extension);
            }).toList();
          });
          break;
        case "trash":
          if(isTrashView) {
            setState(() {
              isTrashView = false;
            });
          } else {
            await _fetchTrash();
            isTrashView = true;
          }
          break;
        default:
          break;
      }
    }

    Widget gridView(BuildContext listContext) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none, // Remove bottom border when not focused
                  focusedBorder: InputBorder.none,  // Remove bottom border when focused
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  performSearch(value);
                },
              ),
            ),
          ),
          // Scrollable Content with RefreshIndicator
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshPage,
              color: Colors.blue,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    controller: _scrollController,
                    physics: AlwaysScrollableScrollPhysics(), // Ensures pull-to-refresh always works
                    child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight, // Ensure minimum height is screen height
                      ),
                      child: Column(
                        children: [
                          if (getPaginatedItems().isNotEmpty) ...[
                            GridView.builder(
                              shrinkWrap: true, // Ensures it takes only necessary space
                              physics: NeverScrollableScrollPhysics(), // Prevents inner scrolling conflict
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3, // Set number of columns
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                                childAspectRatio: 1.2,
                              ),
                              itemCount: getPaginatedItems().length,
                              itemBuilder: (context, index) {
                                final item = getPaginatedItems()[index];
                                bool isSelected = selectedItems.contains(item);
                                bool isPrivate = item['link_pass'].toString() == "1";
                                bool isOnlyMe = item['only_me'].toString() == "1";
                                bool isFolder = !item.containsKey('file_code');
                                bool isCrypted = (item.containsKey('file_code') && item['encrypted'].toString() != "null") || item['fld_encrypted'].toString() == "1";

                                return GestureDetector(
                                  onLongPress: () => toggleSelectionMode(item),
                                  onTap: () {
                                    if (selectionMode) {
                                      toggleSelectionMode(item);
                                    } else {
                                      item.containsKey('file_code')
                                          ? openCloudFile(listContext, item['file_code'], item['name'])
                                          : _openCloudFolder(context, item);
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey, // Border color
                                        width: 0.5, // Border width
                                      ),
                                      borderRadius: BorderRadius.circular(8), // Optional: rounded corners
                                    ),
                                    child: GridTile(
                                      header: Align(
                                        alignment: Alignment.topRight,
                                        child: IconButton(
                                          icon: Icon(
                                            selectionMode
                                                ? (isSelected ? Icons.check_circle : Icons.radio_button_unchecked)
                                                : Icons.more_vert,
                                            color: isSelected ? Colors.blue : null,
                                          ),
                                          onPressed: selectionMode
                                              ? () => toggleSelectionMode(item)
                                              : () => _showOptions(context, item),
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Stack(
                                            children: [
                                              item.containsKey('file_code')
                                                  ? Image.network(
                                                      item['thumbnail'],
                                                      width: 60,
                                                      height: 60,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context, error, stackTrace) {
                                                        return getFileIcon(item['name']);
                                                      },
                                                    )
                                                  : Icon(
                                                      Icons.folder,
                                                      size: 60,
                                                      color: isSelected ? Colors.cyan : Colors.blue,
                                                    ),
                                              // Lock Icon for Private Files
                                              if (isPrivate)
                                                Positioned(
                                                  top: -5,
                                                  left: -5,
                                                  child: Container(
                                                    padding: EdgeInsets.all(4),
                                                    child: Icon(
                                                      Icons.lock,
                                                      size: 16,
                                                      color: Colors.green,
                                                    ),
                                                  ),
                                                ),
                                              if (isFolder)
                                                if (item["total_files"].toString() != "null")
                                                  Positioned(
                                                    top: 6,
                                                    left: 6,
                                                    child: Container(
                                                      padding: EdgeInsets.all(4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Text(
                                                        item["total_files"].toString(),
                                                        style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ),
                                              if (isCrypted)
                                                Positioned(
                                                  bottom: 8, // Adjust this value to position it just below the icon
                                                  left: 0,
                                                  right: 0,
                                                  child: IntrinsicWidth(
                                                    // Ensures the width fits the content
                                                    child: Container(
                                                      padding:
                                                          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Center(
                                                        // Ensures the text is centered inside the container
                                                        child: Text(
                                                          "SSCE",
                                                          textAlign: TextAlign.center,
                                                          style: TextStyle(
                                                            color: Color.fromARGB(255, 180, 243, 168),
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              // Selection Overlay
                                              if (isSelected)
                                                Positioned.fill(
                                                  child: Container(
                                                    color: Colors.blue.withOpacity(0.5),
                                                    child: Icon(Icons.check, color: Colors.white, size: 40),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            isOnlyMe ? "${item['name']} (Only Me)" : item['name'],
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
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

                          // Add empty space **only if needed**
                          Builder(
                            builder: (context) {
                              double totalItemsHeight = (getPaginatedItems().length / 3).ceil() * 100.0;
                              double remainingHeight = constraints.maxHeight - totalItemsHeight;
                              return remainingHeight > 0 ? SizedBox(height: remainingHeight) : SizedBox();
                            },
                          ),
                        ],
                      ),
                    ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Pagination Controls (Now outside RefreshIndicator)
          if (totalItems > itemsPerPage && itemsPerPage > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
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
                      backgroundColor: Colors.blue,
                    ),
                    child: Text("Previous", style: TextStyle(color: Colors.white)),
                  ),
                  ElevatedButton(
                    onPressed: () => showGoToPageDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
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
                      backgroundColor: Colors.blue,
                    ),
                    child: Text("Next", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    Widget listView(BuildContext listContext) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none, // Remove bottom border when not focused
                  focusedBorder: InputBorder.none,  // Remove bottom border when focused
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  performSearch(value);
                },
              ),
            ),
          ),
          // Scrollable Content with RefreshIndicator
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshPage,
              color: Colors.blue,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    controller: _scrollController,
                    physics: AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        children: [
                          if (getPaginatedItems().isNotEmpty) ...[
                            // Display Folders
                            if (folders.isNotEmpty)
                              ...getPaginatedItems()
                                  .where((item) => !item.containsKey('file_code'))
                                  .map((folder) {
                                    bool isSelected = selectedItems.contains(folder);
                                    bool isCrypted = folder['fld_encrypted'].toString() == "1";

                                    return Column(
                                      children: [
                                        GestureDetector(
                                          onLongPress: () => toggleSelectionMode(folder),
                                          onTap: () {
                                            if (selectionMode) {
                                              toggleSelectionMode(folder);
                                            } else {
                                              _openCloudFolder(context, folder);
                                            }
                                          },
                                          child: ListTile(
                                            leading: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Icon(
                                                  folder['name'] == 'Trash' ? Icons.delete : Icons.folder,
                                                  size: 40,
                                                  color: isSelected ? Colors.cyan : Colors.blue,
                                                ),
                                                if (folder["total_files"].toString() != "null")
                                                  Positioned(
                                                    top: -5,
                                                    left: -5,
                                                    child: Container(
                                                      padding: EdgeInsets.all(4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Text(
                                                        folder["total_files"].toString(),
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (isCrypted)
                                                  Positioned(
                                                    bottom: 6,
                                                    left: 0,
                                                    right: 0,
                                                    child: IntrinsicWidth(
                                                      child: Container(
                                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green,
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            "SSCE",
                                                            textAlign: TextAlign.center,
                                                            style: TextStyle(
                                                              color: Color.fromARGB(255, 180, 243, 168),
                                                              fontSize: 8,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
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
                                        ),
                                        Divider(
                                          color: const Color.fromARGB(255, 201, 201, 201),
                                          height: 1,
                                          thickness: 0.25,
                                          indent: 16,
                                          endIndent: 16,
                                        ),
                                      ],
                                    );
                                  }).toList(),

                            // Display Files
                            if (files.isNotEmpty)
                              ...getPaginatedItems().where((item) => item.containsKey('file_code')).map((file) {
                                bool isSelected = selectedItems.contains(file);
                                bool isCrypted = file['encrypted'].toString() != "null";
                                return Column(
                                  children: [
                                    GestureDetector(
                                      onLongPress: () => toggleSelectionMode(file),
                                      onTap: () {
                                        if (selectionMode) {
                                          toggleSelectionMode(file);
                                        } else {
                                          openCloudFile(listContext, file['file_code'], file['name']);
                                        }
                                      },
                                      child: ListTile(
                                        leading: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Image.network(
                                              file['thumbnail'],
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                                                return getFileIcon(file['name']);
                                              },
                                            ),
                                            if (file['link_pass'].toString() == "1") // Check if link_pass is 1
                                              Positioned(
                                                top: -5,
                                                left: -5,
                                                child: Icon(Icons.lock, color: Colors.green, size: 16),
                                              ),
                                            if (isCrypted)
                                              Positioned(
                                                bottom: 2, // Adjust this value to position it just below the icon
                                                left: 0,
                                                right: 0,
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    "SSCE",
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
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
                                        title: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              shortenName(file['name']),
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              (file['size'] ?? 'Size not available') + 
                                              (file['only_me'].toString() == '1' ? ' | Only Me' : ''),
                                              style: TextStyle(color: Colors.grey, fontSize: 12),
                                            ),
                                            Text(
                                              file['uploaded'] ?? 'Date not available',  // Replace 'modified_date' with the actual field you want to display
                                              style: TextStyle(color: Colors.grey, fontSize: 12),
                                            ),
                                          ],
                                        ),
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
                                    ),
                                    Divider(
                                      color: const Color.fromARGB(255, 201, 201, 201),
                                      height: 1,
                                      thickness: 0.25,
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                  ]
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

                          // Add empty space **only if needed**
                          Builder(
                            builder: (context) {
                              double totalItemsHeight = getPaginatedItems().length * 60.0;
                              double remainingHeight = constraints.maxHeight - totalItemsHeight;
                              return remainingHeight > 0 ? SizedBox(height: remainingHeight) : SizedBox();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Pagination Controls (Now outside RefreshIndicator)
          if (totalItems > itemsPerPage && itemsPerPage > 0) 
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
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
                      backgroundColor: Colors.blue,
                    ),
                    child: Text(
                      "Previous",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => showGoToPageDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
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
                      backgroundColor: Colors.blue,
                    ),
                    child: Text(
                      "Next",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          selectionMode
              ? "${selectedItems.length} selected"
              : (visitedFolderIDs.last.last != '/'
                  ? visitedFolderIDs.last.last
                  : 'My Files'),
        ),
        leading: IconButton(
          icon: Icon(selectionMode ? Icons.close : Icons.arrow_back, color: Colors.blue),
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
              icon: Icon(Icons.sort, color: Colors.blue),
              onPressed: () {
                final RenderBox renderBox = context.findRenderObject() as RenderBox;
                final Offset offset = renderBox.localToGlobal(Offset.zero);
                
                showMenu<String>(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    offset.dx, 
                    offset.dy + renderBox.size.height, // Directly below the icon
                    offset.dx + renderBox.size.width,
                    offset.dy + renderBox.size.height + 300, // Ensures dropdown grows downward
                  ),
                  items: <PopupMenuEntry<String>>[  // Explicitly defining the type
                    PopupMenuItem<String>(
                      value: 'grid',
                      child: ListTile(
                        leading: Icon(Icons.grid_view),
                        title: Text('Grid View'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'list',
                      child: ListTile(
                        leading: Icon(Icons.list),
                        title: Text('List View'),
                      ),
                    ),
                    PopupMenuDivider(),  // This is fine, no need for a type here
                    PopupMenuItem<String>(
                      value: 'name',
                      child: ListTile(
                        leading: Icon(Icons.sort_by_alpha),
                        title: Text('Sort by Name'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'date',
                      child: ListTile(
                        leading: Icon(Icons.access_time),
                        title: Text('Sort by Date'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'size',
                      child: ListTile(
                        leading: Icon(Icons.storage),
                        title: Text('Sort by Size'),
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'video',
                      child: ListTile(
                        leading: Icon(Icons.movie),
                        title: Text('Videos'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'audio',
                      child: ListTile(
                        leading: Icon(Icons.audiotrack),
                        title: Text('Audio'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'photo',
                      child: ListTile(
                        leading: Icon(Icons.image),
                        title: Text('Photos'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'document',
                      child: ListTile(
                        leading: Icon(Icons.description),
                        title: Text('Documents'),
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'trash',
                      child: ListTile(
                        leading: Icon(Icons.delete),
                        title: Text(isTrashView ? 'Hide Trash' : 'View Trash'),
                      ),
                    ),
                  ],
                ).then((value) {
                  if (value != null) {
                    handleMenuSelection(value);
                  }
                });

              },
            ),
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
      floatingActionButton: _isPlusButtonVisible
          ? Stack(
              children: [
                Positioned(
                  right: 16,
                  bottom: (itemsPerPage > 0) ? 50 : 16,
                  child: Material(
                    shape: CircleBorder(), // Maintain circular shape for the FAB
                    child: FloatingActionButton(
                      onPressed: () {
                        _showAddOptionsDialog(context);
                      },
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.add, color: Colors.white),
                    ),
                  ),
                ),
                if (copyStatus != 0)
                  Positioned(
                    left: 16,
                    bottom: (itemsPerPage > 0) ? 50 : 16,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: FloatingActionButton(
                        onPressed: _pasteFile,
                        child: Icon(Icons.paste, color: Colors.blue),
                      ),
                    ),
                  ),
              ],
            )
          : Container(),
      body: isLoading
          ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)))
          : isGridView ? gridView(context) : listView(context),
    );

  }

  // Show options (Rename, Copy, Move To, Download, Remove) for file/folder
  void _showOptions(BuildContext context, dynamic item) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return FileOptions(
          item: item,
          selectedItems: selectedItems,
          getSelectedType: getSelectedType(item),
          onRename: () {
            Navigator.pop(context);
            _showRenameDialog(context, item);
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
                mainFeature.addDownloadingQueue({
                  "fileCode": item['file_code'], 
                  "fileName": item['name'], 
                  "filePath": subpath
                });
              } else {
                await mainFeature.downloadFolder(item['fld_id'], "$subpath/${item['name']}");
              }
            } else {
              for (dynamic selectedItem in selectedItems) {
                if (selectedItem.containsKey('file_code')) {
                  mainFeature.addDownloadingQueue({
                    "fileCode": selectedItem['file_code'], 
                    "fileName": selectedItem['name'], 
                    "filePath": subpath
                  });
                } else {
                  await mainFeature.downloadFolder(selectedItem['fld_id'], "$subpath/${selectedItem['name']}");
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
              await mainFeature.removeCloudItem(item);
            } else {
              for (dynamic selectedItem in selectedItems) {
                await mainFeature.removeCloudItem(selectedItem);
              }
            }
            setState(() {
              selectedItems = [];
              isLoading = false;
            });
            _fetchFilesAndFolders(visitedFolderIDs.last.first.toString());
          },
          onShare: () async {
            Navigator.pop(context);
            setState(() {
              isLoading = true;
            });
            if (item != "") {
              await mainFeature.shareItem(item);
            } else {
              for (dynamic selectedItem in selectedItems) {
                await mainFeature.shareItem(selectedItem);
              }
            }
            setState(() {
              selectedItems = [];
              isLoading = false;
            });
            _fetchFilesAndFolders(visitedFolderIDs.last.first.toString());
          },
          onSetPW: () async {
            Navigator.pop(context);
            if(item != "") {
              if (item['link_pass'].toString() == "1") {
                _unsetPassword(item);
              } else {
                _setPasswordDialog(context, item);
              }
            } else {
              bool isAllSet = true;
              for (int i = 0; i < selectedItems.length; i ++) {
                if (selectedItems[i]['link_pass'].toString() == "0") {
                  isAllSet = false;
                }
              }
              if (isAllSet) {
                _unsetPassword(item);
              } else {
                _setPasswordDialog(context, item);
              }
            }
          },
          onNativeShare: () async {
            onNativeShare(context, item);
          },
          onRestore: () async {
            Navigator.pop(context);
            setState(() {
              isLoading = true;
            });
            if (item != "") {
              await mainFeature.restoreCloudItem(item);
            } else {
              for (dynamic selectedItem in selectedItems) {
                await mainFeature.restoreCloudItem(selectedItem);
              }
            }
            setState(() {
              selectedItems = [];
              isLoading = false;
            });
            _fetchFilesAndFolders(visitedFolderIDs.last.first.toString());
          }
        );
      },
    );
  }

  // Open Cloud Folder and show Files/Folders in it.
  void _openCloudFolder(BuildContext context, dynamic item) async {
    if (item['name'] == 'Trash') {
      setState(() {
        folders = deletedFolders;
        files = deletedFiles;
      });
    } else {
      try {
        await _fetchFilesAndFolders(item["fld_id"], hotReload: false);
        visitedFolderIDs.add([item['fld_id'], item['name']]);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _refreshPage() async {
    dynamic item = visitedFolderIDs.last;
    try {
      mainFeature.cachedFolderInfo.remove(item.first.toString());
      await _fetchFilesAndFolders(item.first);
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
        if (['txt',].contains(fileExtension)) {
          _showTextFile(context, file);
        } else if (['mp3', 'wav', 'aac', 'ogg', 'm4a', 'flac', 'wma'].contains(fileExtension)) {
          _playAudioFile(context, file);
        } else if (['mp4', 'mov', 'mkv', 'avi', 'flv', 'wmv', 'webm'].contains(fileExtension)) {
          _playVideoFile(context, file);
        } else if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'tiff', 'tif', 'webp'].contains(fileExtension)) {
          _showImageFile(context, file);
        } else {
          _openDocumentFile(context, file);
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

  Future<void> _openDocumentFile(BuildContext context, File file) async {
    String filePath = file.path;
    String fileExtension = filePath.split('.').last.toLowerCase();

    // Attempt to open the document
    final result = await OpenFile.open(filePath);

    // Handle the result
    if (result.message != 'Success') {
      // Show an error message if the file could not be opened
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open file: ${result.message}')),
      );
    }
  }

  // Show text file content
  void _showTextFile(BuildContext context, File file) async {
    String content = await file.readAsString();
    print("content: $content");
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
      await _fetchFilesAndFolders(visitedFolderIDs.last.first, hotReload: false);
    } catch (e) {
      print(e);
      _fetchFilesAndFolders(0, hotReload: false);
      visitedFolderIDs = [[0, '/'], [0, '/']];
    }
  }

  void _homeCloudFolder() async {
    try {
      visitedFolderIDs = [[0, '/'], [0, '/']];
      await _fetchFilesAndFolders(visitedFolderIDs.last.first, hotReload: false);
    } catch (e) {
      print(e);
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
                await mainFeature.renameFile(item, controller.text);
                await _fetchFilesAndFolders(visitedFolderIDs.last.first);
                setState(() {
                  isLoading = false;
                });
              },
              child: Text('Rename', style: TextStyle(color: Colors.blue),),
            ),
          ],
        );
      },
    );
  }

  void _setPasswordDialog(BuildContext context, dynamic item) {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Set Password'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Type Password Here.',
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
                if (item != "") {
                  await mainFeature.lockItem(item, controller.text);
                } else {
                  for (dynamic selectedItem in selectedItems) {
                    await mainFeature.lockItem(selectedItem, controller.text);
                  }
                }
                await _fetchFilesAndFolders(visitedFolderIDs.last.first);
                setState(() {
                  isLoading = false;
                  selectedItems = [];
                });
              },
              child: Text('Lock File', style: TextStyle(color: Colors.blue),),
            ),
          ],
        );
      },
    );
  }

  Future<void> _unsetPassword(dynamic item) async {
    setState(() {
      isLoading = true;
    });
    if (item != "") {
      await mainFeature.lockItem(item, "");
    } else {
      for (dynamic selectedItem in selectedItems) {
        await mainFeature.lockItem(selectedItem, "");
      }
    }
    await _fetchFilesAndFolders(visitedFolderIDs.last.first);
    setState(() {
      isLoading = false;
      selectedItems = [];
    });
  }

  void onNativeShare(BuildContext context, Map<String, dynamic> item) async {
    if (item.containsKey('link')) {
      // Share the link using the share_plus package
      await Share.share(item['link'], subject: 'Check out this link!');
      
      // Optionally show a confirmation dialog
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Share Link'),
            content: Text('The share link has been shared successfully.'),
            actions: <Widget>[
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
              ),
            ],
          );
        },
      );
    }
  }

  int getSelectedType(dynamic item) { // 0: normal, 1: only file, 2: trashed
    if (item != "") {
      if (item.containsKey('trashed')) return 2;
      if (item.containsKey('file_code')) {
        return 1;
      } else {
        return 0;
      }
    } else {
      for (int i = 0; i < selectedItems.length; i ++) {
        if (selectedItems[i].containsKey('trashed')) return 2;
        if (!selectedItems[i].containsKey('file_code')) {
          return 0;
        }
      }
      return 1;
    }
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
      isLoading = true;
    });
    String folderID = visitedFolderIDs.last.first.toString();
    for(dynamic copiedFileFolder in copiedFileFolders){
      if (copyStatus == 1 && copiedFileFolder.containsKey('file_code')) {  // copy file.
        String fileCode = copiedFileFolder['file_code'];
        final response = await mainFeature.getAPICall('$baseURL/file/clone?file_code=$fileCode&sess_id=${mainFeature.sessionId}');
        var data = jsonDecode(response.body);
        String clonedFileCode = data['result']['filecode'];
        await mainFeature.getAPICall('$baseURL/file/set_folder?file_code=$clonedFileCode&fld_id=$folderID&sess_id=${mainFeature.sessionId}');
        print('Successfully copied.');
      } else if (copyStatus == 2 && copiedFileFolder.containsKey('file_code')) { // move file.
        String fileCode = copiedFileFolder['file_code'];
        await mainFeature.getAPICall('$baseURL/file/set_folder?file_code=$fileCode&fld_id=$folderID&sess_id=${mainFeature.sessionId}');
        print('Successfully moved.');
      } else if (copyStatus == 1 && !copiedFileFolder.containsKey('file_code')) { // copy folder.
        String copyFolderID = copiedFileFolder['fld_id'].toString();
        final response = await mainFeature.getAPICall('$baseURL/folder/copy?fld_id=$copyFolderID&sess_id=${mainFeature.sessionId}');
        var data = jsonDecode(response.body);
        String clonedFolderID = data['result']['fld_id'].toString();
        final response1 = await mainFeature.getAPICall('$baseURL/folder/move?fld_id=$clonedFolderID&dest_fld_id=$folderID&sess_id=${mainFeature.sessionId}');
        mainFeature.renameFile(jsonDecode(response1.body)['result'], copiedFileFolder['name']);
        print('Successfully copied.');
      } else if (copyStatus == 2 && !copiedFileFolder.containsKey('file_code')) { // move folder.
        String moveFolderID = copiedFileFolder['fld_id'].toString();
        await mainFeature.getAPICall('$baseURL/folder/move?fld_id=$moveFolderID&dest_fld_id=$folderID&sess_id=${mainFeature.sessionId}');
        print('Successfully moved.');
      } else {
        print('Nothing to paste.');
      }
    }
    copyStatus = 0;
    await _fetchFilesAndFolders(copiedFileFolders.first['fld_id']);
    copiedFileFolders = [];
    await _fetchFilesAndFolders(visitedFolderIDs.last.first.toString());
    setState(() {
      isLoading = false;
    });
  }

  Future<void> createFolderIfNotExists(String path) async {
    final directory = Directory(path);

    // Check if the directory exists
    if (await directory.exists()) {
    } else {
      // Create the directory
      await directory.create(recursive: true);
    }
  }

  // Fetch files and folders using the API
  Future<dynamic> fetchFilesAndFolders(fldId) async {
    final response = await mainFeature.getAPICall('$baseURL/folder/list?fld_id=${fldId.toString()}&sess_id=${mainFeature.sessionId}');
    var data = jsonDecode(response.body);
    return data['result'];
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
                  mainFeature.fromToday = true;
                });
                mainFeature._startBackup();
                Navigator.pop(context);
              },
              child: Text("Today Only", style: TextStyle(color: Colors.blue)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  fromToday = false;
                  mainFeature.fromToday = false;
                });
                mainFeature._startBackup();
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
      // mainFeature._startBackup();
    }
    if (prefs.getString('last_backup_date') != "") {
      // print("last_backup_date: ${prefs.getString('last_backup_date')}");
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

  Future<void> _pickFiles() async {
    List<String> selectedFiles = [];
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null) {
        selectedFiles = result.paths.map((path) => path!).toList();
        for(int i = 0; i < selectedFiles.length; i ++) {
          String filePath = selectedFiles[i];
          mainFeature.addUploadQueue({
            "filePath": filePath,
            "folderID": visitedFolderIDs.last.first.toString()
          });
        }
        mainFeature.changeTab(2);
      }
    } catch (e) {
      // Handle error
      print('Error picking files: $e');
    } finally {
    }
  }

  void _openURL(String url) async {
    Uri uri = Uri.parse(url);

    if (Platform.isWindows) {
      // Use `Process.start` on Windows instead of `launchUrl`
      await Process.start('explorer.exe', [url]);
    } else {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.inAppWebView);
      } else {
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

  void _showAddOptionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Choose an action"),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.create_new_folder, color: Colors.blue),
                  title: Text("Create Folder"),
                  onTap: () {
                    Navigator.pop(context);
                    _createFolderDialog(context);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.note_add, color: Colors.blue),
                  title: Text("Create Quick Note"),
                  onTap: () {
                    Navigator.pop(context);
                    _createQuickNoteDialog(context);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.upload_file, color: Colors.blue),
                  title: Text("Upload Files"),
                  onTap: () {
                    Navigator.pop(context);
                    _pickFiles();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.folder_open, color: Colors.blue),
                  title: Text("Select Folder"),
                  onTap: () {
                    Navigator.pop(context);
                    _selectFolder();
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text("Cancel", style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _createFolderDialog(BuildContext context) {
    TextEditingController folderNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Create Folder"),
          content: TextField(
            controller: folderNameController,
            decoration: InputDecoration(hintText: "Enter folder name"),
          ),
          actions: <Widget>[
            TextButton(
              child: Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text("Create"),
              onPressed: () async {
                String folderName = folderNameController.text.trim();
                if (folderName.isNotEmpty) {
                  try {
                    await mainFeature.createCloudFolder(folderName, visitedFolderIDs.last.first.toString());
                    Navigator.of(context).pop();
                    _refreshPage();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Folder '$folderName' created successfully")),
                    );
                  } catch (e) {
                    // Handle errors
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to create folder: $e")),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _createQuickNoteDialog(BuildContext context) {
    TextEditingController noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Create Quick Note"),
          content: TextField(
            controller: noteController,
            maxLines: 5,
            decoration: InputDecoration(hintText: "Enter your note"),
          ),
          actions: <Widget>[
            TextButton(
              child: Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text("Save & Upload"),
              onPressed: () {
                String noteText = noteController.text.trim();
                if (noteText.isNotEmpty) {
                  Navigator.of(context).pop(); // Close first dialog

                  // Delay opening the second dialog to ensure the first one is closed
                  Future.delayed(Duration.zero, () {
                    _uploadNoteDialog(context, noteText);
                  });
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _uploadNoteDialog(BuildContext context, String note) {
    TextEditingController fileNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Save Note"),
          content: TextField(
            controller: fileNameController,
            decoration: InputDecoration(hintText: "Enter file name"),
          ),
          actions: <Widget>[
            TextButton(
              child: Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text("Save"),
              onPressed: () {
                String fileName = fileNameController.text.trim();
                if (fileName.isNotEmpty) {
                  Navigator.of(context).pop(); // Close file name dialog
                  _uploadNoteAsFile(fileName, note); // Upload note
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("File name cannot be empty")),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _uploadNoteAsFile(String fileName, String note) async {
    try {
      // Get the temporary directory
      final directory = await getTemporaryDirectory();
      final filePath = "${directory.path}/$fileName.txt";
      final file = File(filePath);

      // Write the note content to the file
      await file.writeAsString(note);
      print("Note saved as: $filePath");

      // Add file to upload queue
      mainFeature.addUploadQueue({'filePath': filePath, 'folderID': visitedFolderIDs.last.first.toString()});

      // Schedule file deletion after some time (optional)
      Future.delayed(Duration(minutes: 10), () async {
        if (await file.exists()) {
          await file.delete();
          print("Temporary file deleted: $filePath");
        }
      });
    } catch (e) {
      print("Error saving or uploading note: $e");
    }
  }

  Future<void> _selectFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        print("Selected Folder: $selectedDirectory");

        String folderID = "";
        for(int i = 0; i < folders.length; i ++) {
          if(folders[i]['name'] == selectedDirectory.split('/').last.split(r'\').last) {
            folderID = folders[i]['folder_id'];
          }
        }
        if (folderID == "") {
          folderID = await mainFeature.createCloudFolder(selectedDirectory.split('/').last.split(r'\').last, visitedFolderIDs.last.first.toString());
        }
        
        mainFeature.uploadFolder(selectedDirectory, folderID);
        mainFeature.changeTab(2);
        print("All files in the folder added to upload queue.");
      } else {
        print("Folder selection canceled.");
      }
    } catch (e) {
      print("Error selecting folder: $e");
    }
  }

  void _selectMedia() {
    print("Selecting media...");
    // Implement media selection logic (photos & videos)
  }

  void _captureMedia() {
    print("Capturing photo or video...");
    // Implement capture media logic (take photo/record video)
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
  final List<dynamic> selectedItems;
  final int getSelectedType;
  final VoidCallback onRename;
  final VoidCallback onCopy;
  final VoidCallback onMove;
  final VoidCallback onDownload;
  final VoidCallback onRemove;
  final VoidCallback onShare;
  final VoidCallback onSetPW;
  final VoidCallback onNativeShare;
  final VoidCallback onRestore;

  const FileOptions({
    required this.item,
    required this.selectedItems,
    required this.getSelectedType,
    required this.onRename,
    required this.onCopy,
    required this.onMove,
    required this.onDownload,
    required this.onRemove,
    required this.onShare,
    required this.onSetPW,
    required this.onNativeShare,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    if (getSelectedType == 2) {
      return ListTile(
          title: Text('Restore'),
          onTap: onRestore,
        );
    }
    return ListView(
      children: [
        if (item != "")
          Container(
            height: 40.0, // Adjust height as needed
            child: ListTile(
              title: Text('Rename'),
              onTap: onRename,
            ),
          ),
        Container(
          height: 40.0,
          child: ListTile(
            title: Text('Copy'),
            onTap: onCopy,
          ),
        ),
        Container(
          height: 40.0,
          child: ListTile(
            title: Text('Move To'),
            onTap: onMove,
          ),
        ),
        Container(
          height: 40.0,
          child: ListTile(
            title: Text('Download'),
            onTap: onDownload,
          ),
        ),
        Container(
          height: 40.0,
          child: ListTile(
            title: Text('Remove'),
            onTap: onRemove,
          ),
        ),
        if (getSelectedType == 1)
          Container(
            height: 40.0,
            child: ListTile(
              title: Text('Sharing/Only-Me'),
              onTap: onShare,
            ),
          ),
        if (getSelectedType == 1)
          Container(
            height: 40.0,
            child: ListTile(
              title: Text('Share Link'),
              onTap: onNativeShare,
            ),
          ),
        if (getSelectedType == 1)
          Container(
            height: 40.0,
            child: ListTile(
              title: Text(
                item != ""
                    ? (item['link_pass'].toString() == "1" ? "Unset Password" : "Set Password")
                    : (() {
                        bool isAllSet = true;
                        for (int i = 0; i < selectedItems.length; i++) {
                          if (selectedItems[i]['link_pass'].toString() == "0") {
                            isAllSet = false;
                            break; // Exit loop early if any item is not set
                          }
                        }
                        return isAllSet ? "Unset Password" : "Set Password";
                      }()),
              ),
              onTap: onSetPW,
            ),
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
  dynamic syncedFileFolders = {};
  final MainFeature mainFeature;
  bool isLoading = false;
  Isolate? _backgroundIsolate;
  bool isSyncing = false;

  final ScrollController _scrollController = ScrollController();
  bool _isPlusButtonVisible = true;

  _SyncPageState({required this.mainFeature});

  @override
  void initState() {
    super.initState();
    _loadSyncOrders();
    _watchFileCDM();
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
      // User is scrolling down, hide the FAB
      if (_isPlusButtonVisible) {
        setState(() {
          _isPlusButtonVisible = false;
        });
      }
    } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
      // User is scrolling up, show the FAB
      if (!_isPlusButtonVisible) {
        setState(() {
          _isPlusButtonVisible = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
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
            // TODO: Upload file or perform necessary actions
            break;
          case 'delete':
            // TODO: Handle file deletion
            break;
          case 'modify':
            // TODO: Handle file modification
            break;
          case 'move':
            // TODO: Handle file move
            break;
          default:
        }
      }
    });
  }

  /// Load sync orders from local storage
  Future<void> _loadSyncOrders() async {
    syncOrders = mainFeature.syncOrders;
    syncedFileFolders = mainFeature.syncedFileFolders;
    syncedFiles = mainFeature.syncedFiles;
  }

  /// Save sync orders to local storage
  Future<void> _saveSyncOrders() async {
    final prefs = await SharedPreferences.getInstance();
    String encodedOrders = jsonEncode(mainFeature.syncOrders.map((e) => e.toJson()).toList());
    await prefs.setString('sync_orders', encodedOrders);
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
      mainFeature.syncOrders.add(SyncOrder(localPath: localPath, syncType: syncType, remotePath: remotePath, fld_id: currentRemoteFldID));
      _toggleSync(mainFeature.syncOrders.length - 1);
    });
  }

  /// Delete Sync Order
  void _deleteSyncOrder(int index) {
    setState(() {
      mainFeature.syncOrders.removeAt(index);
    });
    _saveSyncOrders();
  }

  /// Start/Stop Sync Order
  void _toggleSync(int index) async {
    setState(() {
      mainFeature.syncOrders[index].isRunning = !mainFeature.syncOrders[index].isRunning;
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

  Future<String> getFolderID(String folderName, String parentFolderID) async {
    final response = await mainFeature.getAPICall('$baseURL/folder/list?fld_id=$parentFolderID&sess_id=${mainFeature.sessionId}');
    var data = jsonDecode(response.body);
    List<String> cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
    List<String> cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));
    for (int i = 0; i < cloudFolders.length; i ++) {
      if (cloudFolders[i] == folderName) {
        return cloudFolderCodes[i];
      }
    }
    final response1 = await mainFeature.getAPICall('$baseURL/folder/create?parent_id=$parentFolderID&name=$folderName&sess_id=${mainFeature.sessionId}');
    var data1 = jsonDecode(response1.body);
    return data1['result']['fld_id'].toString();
  }

  Future<String> createCloudFolder(String localFolder, String parentId) async {
    final response = await mainFeature.getAPICall('$baseURL/folder/create?parent_id=$parentId&name=$localFolder&sess_id=${mainFeature.sessionId}');
    var data = jsonDecode(response.body);
    return data['result']['fld_id'].toString();
  }

  Future<void> createFolderIfNotExists(String path) async {
    final directory = Directory(path);

    // Check if the directory exists
    if (await directory.exists()) {
    } else {
      // Create the directory
      await directory.create(recursive: true);
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
      floatingActionButton: _isPlusButtonVisible
        ? FloatingActionButton(
            onPressed: _showAddSyncOrderDialog,
            backgroundColor: Colors.blue,
            child: Icon(Icons.add, color: Colors.white),
          )
        : Container(),
      body: isLoading
            ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)),) // Show loading indicator
            : Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: mainFeature.syncOrders.length,
              itemBuilder: (context, index) {
                final order = mainFeature.syncOrders[index];
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
    for (int i = 0; i< selectedFiles.length; i ++) {
      String filePath = selectedFiles[i];
      mainFeature.addUploadQueue({
        "filePath": filePath,
        "folderID": "0"
      });
      // await uploader.uploadFile(filePath, "0");
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
    final response = await mainFeature.getAPICall('$baseURL/folder/list?fld_id=$parentFolderID&sess_id=${mainFeature.sessionId}');
    var data = jsonDecode(response.body);
    List<String> cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
    List<String> cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));
    for (int i = 0; i < cloudFolders.length; i ++) {
      if (cloudFolders[i] == folderName) {
        return cloudFolderCodes[i];
      }
    }
    return "";
  }

  Future<void> _pickFiles() async {
    setState(() {
      isLoading = true;
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
    final response = await mainFeature.getAPICall('$baseURL/folder/create?parent_id=$parentId&name=$localFolder&sess_id=${mainFeature.sessionId}');
    var data = jsonDecode(response.body);
    return data['result']['fld_id'].toString();
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

class Transfer extends StatefulWidget {
  final MainFeature mainFeature;
  Transfer({required this.mainFeature});

  @override
  _TransferState createState() => _TransferState(mainFeature: mainFeature);
}

class _TransferState extends State<Transfer> {
  final MainFeature mainFeature;

  _TransferState({required this.mainFeature});

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {}); // Refresh UI
        _startTimer();
      }
    });
  }

  String _getFileName(String filePath) {
    return filePath.split('/').last; // Extracts last part of path
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('File Transfers', style: TextStyle(color: Colors.black)),
      ),
      body: mainFeature.uploadQueue.isEmpty && mainFeature.downloadQueue.isEmpty
          ? Center(child: Text("No active transfers"))
          : Padding(
              padding: const EdgeInsets.all(10.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (mainFeature.uploadQueue.isNotEmpty) ...[
                      _buildSectionTitle("Uploads"),
                      _buildFileList(mainFeature.uploadQueue, isUpload: true),
                    ],
                    if (mainFeature.downloadQueue.isNotEmpty) ...[
                      _buildSectionTitle("Downloads"),
                      _buildFileList(mainFeature.downloadQueue, isUpload: false),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Text(
        title,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFileList(List<dynamic> queue, {required bool isUpload}) {
    return ListView.builder(
      shrinkWrap: true, // Prevents infinite height error
      physics: NeverScrollableScrollPhysics(), // Prevents nested scroll issues
      itemCount: queue.length,
      itemBuilder: (context, index) {
        var item = queue[index];
        bool isRemoved = item['isRemoved'] ?? false;
        bool isCompleted = (item['progress'] ?? 0.0) >= 1.0;
        bool isDisabled = isRemoved || isCompleted;
        String fileName = isUpload ? _getFileName(item['filePath']) : item['fileName'];

        return Opacity(
          opacity: isDisabled ? 0.5 : 1.0, // Dim the row if removed
          child: IgnorePointer(
            ignoring: isDisabled, // Disable interaction if removed
            child: ListTile(
              leading: Icon(
                isUpload ? Icons.upload : Icons.download,
                color: isDisabled ? Colors.grey : Colors.blue, // Change color if removed
              ),
              title: Text(
                fileName,
                style: TextStyle(
                  fontSize: 16,
                  color: isDisabled ? Colors.grey : Colors.black, // Gray out text
                ),
              ),
              subtitle: _buildProgressBar(item), // Displays progress
              trailing: IconButton(
                icon: Icon(Icons.close, color: isDisabled ? Colors.grey : Colors.red), // Gray out button
                onPressed: isDisabled ? null : () => _cancelTransfer(index, isUpload),
              ),
            ),
          ),
        );
      },
    );
  }

  void _cancelTransfer(int index, bool isUpload) {
    setState(() {
      if (isUpload) {
        mainFeature.uploadQueue[index]['isRemoved'] = true;
      } else {
        mainFeature.downloadQueue[index]['isRemoved'] = true;
      }
    });
  }

  Widget _buildProgressBar(dynamic file) {
    double progress = file['progress'] ?? 0.0; // Placeholder for progress
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 5,
          backgroundColor: Colors.grey[300], // Light grey background
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue), // Set progress color to blue
        ),
        SizedBox(height: 5),
        Text(
          "${(progress * 100).toStringAsFixed(1)}%",
          style: TextStyle(color: Colors.blue), // Make text blue as well (optional)
        ),
      ],
    );
  }

}

class MyAccount extends StatefulWidget {
  final MainFeature mainFeature;
  MyAccount({required this.mainFeature});

  @override
  _MyAccountState createState() => _MyAccountState(mainFeature: mainFeature);
}

class _MyAccountState extends State<MyAccount> {
  final MainFeature mainFeature;
  dynamic userInfo = {};

  _MyAccountState({required this.mainFeature});

  @override
  void initState() {
    super.initState();
    getUserInfo();
  }

  Future<void> getUserInfo() async {
    setState(() {
      userInfo = mainFeature.userInfo;
    });
  }

  Widget build(BuildContext context) {
    // Sample data
    String email = userInfo['email'];
    String accountType = userInfo['utype'] == "prem" ? "Premium" : "Standard";
    double usedSpace = double.parse(userInfo['storage_used']) * 100;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('My Account', style: TextStyle(color: Colors.black)),
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Email:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Text(email, style: TextStyle(fontSize: 16)),
            SizedBox(height: 20),
            
            Text("Account Type:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Text(accountType, style: TextStyle(fontSize: 16, color: accountType == "Premium" ? Colors.green : Colors.red)),
            SizedBox(height: 20),
            
            Text("Disk Usage:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.grey[300],
                  ),
                ),
                Container(
                  width: MediaQuery.of(context).size.width * (usedSpace / 100),
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            SizedBox(height: 5),
            Text("$usedSpace% occupied", style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

}

class OffLine extends StatefulWidget {
  final MainFeature mainFeature;
  OffLine({required this.mainFeature});

  @override
  _OffLineState createState() => _OffLineState(mainFeature: mainFeature);
}

class _OffLineState extends State<OffLine> {
  final MainFeature mainFeature;

  _OffLineState({required this.mainFeature});

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, size: 80, color: Colors.grey),
              SizedBox(height: 20),
              Text(
                "No network, please connect to the internet then reopen the app.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  mainFeature.isFirstCall = true;
                  mainFeature.initState();
                  Navigator.pop(context);
                },
                child: Text("Retry"),
              ),
            ],
          ),
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
  dynamic cachedFolderInfo = {};
  bool isOffline = false;
  
  List<SyncOrder> syncOrders = [];
  List<List<String>> syncedFiles = [];
  dynamic syncedFileFolders = {};
  bool isSyncing = false;
  Isolate? _backgroundIsolate;
  bool fromToday = false;
  DateTime lastBackupDate = DateTime.now();
  int lastScanCount = -1;
  dynamic userInfo = {};
  int _tabSelected = 0;

  void Function(int)? onTabChanged;

  void changeTab(int index) {
    if (onTabChanged != null) {
      onTabChanged!(index);
    }
  }

  Future<void> initState() async {
    if (isFirstCall) {
      isOffline = false;
      await getSessionId();
      await _initializeServerUrl();
      await _loadSyncOrders();
      _infinitCycling(); 
      _getUserInfo();
    }
    isFirstCall = false;
  }

  dynamic getAPICall(String url) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return response;
      } else if (response.statusCode == 404) {
        isOffline = true;
      }
    } catch (e) {
      print('API call failed: $e');
      isOffline = true;
    }
  }

  Future<void> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    sessionId = prefs.getString('sessionId')!;
  }

  Future<void> _saveGlobal(key, value) async {
    final prefs = await SharedPreferences.getInstance();
    String encodedOrders = jsonEncode(value);
    await prefs.setString(key, encodedOrders);
  }

  void addUploadQueue(dynamic uploadingItem) {
    for (int i = 0; i < uploadQueue.length; i ++) {
      if (uploadQueue[i]['filePath'] == uploadingItem['filePath']
       && uploadQueue[i]['folderID'] == uploadingItem['folderID']) {
        return;
      }
    }
    uploadQueue.add({
      ...uploadingItem,
      'progress': 0.0,
    });
  }

  void addDownloadingQueue(dynamic downloadingItem){
    for (int i = currentDownloadingItemIndex; i < downloadQueue.length; i ++) {
      if (downloadQueue[i]['fileCode'] == downloadingItem['fileCode']
       && downloadQueue[i]['fileName'] == downloadingItem['fileName']
       && downloadQueue[i]['filePath'] == downloadingItem['filePath']) {
        return;
      }
    }
    downloadQueue.add({
      ...downloadingItem,
      'progress': 0.0,
    });
  }

  Future<void> _loadSyncOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedOrders = prefs.getString('sync_orders');
    final String? storedSyncedFiles = prefs.getString('stored_files');
    final dynamic storedSyncedFileFolders = prefs.getString('scanned_data');

    if (storedOrders != null && storedOrders != "" && storedOrders != {}) {
      List<dynamic> decoded = jsonDecode(storedOrders);
      syncOrders = decoded.map((e) => SyncOrder.fromJson(e)).toList();
    }

    if (storedSyncedFiles != null && storedSyncedFiles != "" && storedSyncedFiles != {}) {
      List<dynamic> decoded = jsonDecode(storedSyncedFiles);
      syncedFiles = decoded.map((e) => List<String>.from(e)).toList();
    }

    if (storedSyncedFileFolders != null && storedSyncedFileFolders != "" && storedSyncedFileFolders != {}) {
      syncedFileFolders = jsonDecode(storedSyncedFileFolders);
    }

    if (prefs.getBool('autoCameraBackup') == true) {
      _startBackup();
    }
  }

  Future<void> _infinitCycling() async {
    print("infinitCycling");
    for(int i = 0; i < 5; i ++) {
      if (uploadQueue.isNotEmpty && uploadQueue.length > currentUploadingItemIndex) {
        await uploadFile(
          currentUploadingItemIndex,
          (progress) {
            uploadQueue[currentUploadingItemIndex]['progress'] = progress;
          }
          );
        currentUploadingItemIndex ++;
      }
      if (downloadQueue.isNotEmpty && downloadQueue.length > currentDownloadingItemIndex) {
        downloadFile(currentDownloadingItemIndex);
        currentDownloadingItemIndex ++;
      }
    }
    
    if (!isSyncing) {
      print("!isSyncing");
      isSyncing = true;
      if (uploadQueue.isEmpty || uploadQueue.length == currentUploadingItemIndex) {
        if (downloadQueue.isEmpty || downloadQueue.length == currentDownloadingItemIndex) {
          print("if-if");
          try {
            print("try");
            for (int index = 0; index < syncOrders.length; index++) {
              if (syncOrders[index].isRunning) {
                await _performSync(syncOrders[index]);
              }
            }
          } catch (e) {
            print("catch");
            print("Error during sync: $e");
          } finally {
            print("finally");
            if (currentUploadingItemIndex + currentDownloadingItemIndex > lastScanCount) {
              print("finally - if");
              dynamic scanedData = await _scanCloudFiles("", "0");
              syncedFileFolders = scanedData;
              _saveGlobal('scaned_data', scanedData);
            }
            isSyncing = false;
            lastScanCount = currentUploadingItemIndex + currentDownloadingItemIndex;
          }
        }
      }
    }

    await Future.delayed(Duration(seconds: 3));
    await _infinitCycling();
  }

  Future<void> _initializeServerUrl() async {
    try {
      final response = await getAPICall('$baseURL/upload/server?sess_id=$sessionId');
      var data = jsonDecode(response.body);
      serverUrl = data['result'];
    } catch (e) {
      isOffline = true;
      print("Error fetching upload server: $e");
    }
  }

  Future<void> _getUserInfo() async {
    try {
      final response = await getAPICall('$baseURL/account/info?sess_id=$sessionId');
      var data = jsonDecode(response.body);
      userInfo = data['result'];
    } catch (e) {
      print("Error fetching user info: $e");
      isOffline = true;
      userInfo = "";
    }
  }

  Future<String> uploadFile(
    int index, Function(double) onProgress) async {
    String filePath = uploadQueue[index]['filePath'];
    String folderID = uploadQueue[index]['folderID'];
    if (serverUrl.isEmpty) {
      print("No available upload server. Upload failed.");
      uploadQueue[index]['isRemoved'] = true;
      return "no server";
    }

    File file = File(filePath);
    if (!await file.exists()) {
      print("File does not exist: $filePath");
      uploadQueue[index]['isRemoved'] = true;
      return "no file";
    }

    // Check if the file already exists on cloud
    List<String> cloudFiles = [];
    final response = await getAPICall('$baseURL/folder/list?fld_id=$folderID&sess_id=$sessionId');
    var data = jsonDecode(response.body);
    cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));

    if (cloudFiles.contains(filePath.split('/').last)) {
      uploadQueue[index]['isRemoved'] = true;
      return "already exists";
    }

    try {
      var request = http.MultipartRequest('POST', Uri.parse(serverUrl));
      request.fields.addAll({
        'utype': 'prem',
        'sess_id': sessionId,
      });

      var fileStream = http.ByteStream(file.openRead()); // Read file as stream
      var length = await file.length();

      var multipartFile = http.MultipartFile(
        'file_0',
        fileStream,
        length,
        filename: filePath.split('/').last,
      );

      request.files.add(multipartFile);

      // Track progress
      int uploadedBytes = 0;
      Stream<List<int>> stream = fileStream.transform(
        StreamTransformer.fromHandlers(handleData: (data, sink) {
          uploadedBytes += data.length;
          double progress = uploadedBytes / length;
          onProgress(progress); // Update UI
          sink.add(data);
        }),
      );

      multipartFile = http.MultipartFile('file_0', stream, length, filename: filePath.split('/').last);
      request.files[0] = multipartFile;

      http.StreamedResponse response = await request.send();

      if (response.statusCode == 200) {
        String responseString = await response.stream.bytesToString();
        uploadQueue[index]['progress'] = 1.0;
        print("Upload successful: $responseString");
        final List<dynamic> responseData = jsonDecode(responseString);
        await moveFile(responseData[0]['file_code'], folderID);
        return responseData[0]['file_code'];
      } else {
        print("Upload failed: ${response.reasonPhrase}");
        isOffline = true;
        uploadQueue[index]['isRemoved'] = true;
      }
    } catch (e) {
      print("Upload error: $e");
      uploadQueue[index]['isRemoved'] = true;
      isOffline = true;
    }
    return "went wrong";
  }

  Future<void> uploadFolder(String localPath, String folderID) async {
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
    
    final response = await getAPICall('$baseURL/folder/list?fld_id=$folderID&sess_id=$sessionId');
    var data = jsonDecode(response.body);
    cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
    cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code']));
    cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
    cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));

    for (String file in localFiles) {
      if (!cloudFiles.contains(file)) {
        String filePath = "$localPath${Platform.pathSeparator}$file";
        File uploadFile = File(filePath);
        if (uploadFile.existsSync()) {
          addUploadQueue({
            "filePath": filePath,
            "folderID": folderID,
          });
        }
      }
    }

    for (String localFolder in localFolders) {
      if (!cloudFolders.contains(localFolder)) {
        String newFoldeId = await createCloudFolder(localFolder, folderID);
        await uploadFolder("$localPath/$localFolder", newFoldeId);
      } else {
        await uploadFolder("$localPath/$localFolder", cloudFolderCodes[cloudFolders.indexOf(localFolder)]);
      }
    }
  }

  Future<void> moveFile(String fileCode, String folderID) async {
    try {
      await http.get(Uri.parse('$baseURL/file/set_folder?file_code=$fileCode&fld_id=$folderID&sess_id=$sessionId'));
    } catch (e) {
      isOffline = true;
    }
  }

  Future<String> getFolderID(String folderName, String parentFolderID) async {
    final response = await getAPICall('$baseURL/folder/list?fld_id=$parentFolderID&sess_id=$sessionId');
    var data = jsonDecode(response.body);
    List<String> cloudFolders = List<String>.from(data['result']['folders'].map((folder) => folder['name']));
    List<String> cloudFolderCodes = List<String>.from(data['result']['folders'].map((folder) => folder['fld_id'].toString()));
    for (int i = 0; i < cloudFolders.length; i ++) {
      if (cloudFolders[i] == folderName) {
        return cloudFolderCodes[i];
      }
    }
    return "";
  }

  Future<String> createCloudFolder(String localFolder, String parentId) async {
    final response = await getAPICall('$baseURL/folder/create?parent_id=$parentId&name=$localFolder&sess_id=$sessionId');
    var data = jsonDecode(response.body);
    return data['result']['fld_id'].toString();
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
    final response = await getAPICall('$baseURL/file/direct_link?file_code=$fileCode&sess_id=$sessionId');
    var data = jsonDecode(response.body);
    Uri.parse(data['result']['url']);
    return data['result']['url'];
  }

  Future<void> downloadFile(int index) async {
    String fileCode = downloadQueue[index]['fileCode'];
    String fileName = downloadQueue[index]['fileName'];
    String filePath = downloadQueue[index]['filePath'];
    // String parentDirectory = await getDownloadDirectory();
    // String saveDirectory = "$parentDirectory/$filePath";
    String saveDirectory = filePath;

    try {
      String downloadLink = await _getDownloadLink(fileCode);

      if (Platform.isAndroid) {
        var status = await Permission.storage.request();
        if (!status.isGranted) {
          print("Storage permission denied");
          downloadQueue[index]['isRemoved'] = true;
          return;
        }
      }

      var request = http.Request('GET', Uri.parse(downloadLink));
      var streamedResponse = await http.Client().send(request);

      // Store the request in activeDownloads so it can be canceled later
      activeDownloads[index] = streamedResponse;

      int totalBytes = streamedResponse.contentLength ?? 0;
      int receivedBytes = 0;

      if (streamedResponse.statusCode == 200) {
        String filePath = '$saveDirectory/$fileName';
        File file = File(filePath);

        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }

        var sink = file.openWrite();
        await for (var chunk in streamedResponse.stream) {
          // Check if canceled
          if (downloadQueue[index]['isRemoved'] == true) {
            print("Download canceled: $fileName");
            streamedResponse.stream.listen(null).cancel(); // Cancel stream
            await sink.close();
            file.deleteSync(); // Delete incomplete file
            return;
          }

          receivedBytes += chunk.length;
          sink.add(chunk);

          // Update progress
          double progress = totalBytes > 0 ? receivedBytes / totalBytes : 0.0;
          downloadQueue[index]['progress'] = progress;
        }
        await sink.close();

        print("Download complete! File saved at: $filePath");

        // Mark as completed
        downloadQueue[index]['progress'] = 1.0;
      } else {
        print("Download failed. Server response: ${streamedResponse.statusCode}");
      }
    } catch (e) {
      print("Error downloading file: $e");
    } finally {
      activeDownloads.remove(index); // Remove from active downloads after completion
    }
  }

  Future<void> downloadFolder(String folderID, String folderPath) async {
    List<String> localFiles = [];
    await createFolderIfNotExists(folderPath);
    Directory dir = Directory(folderPath);
    if (dir.existsSync()) {
      localFiles = dir.listSync().whereType<File>().map((e) => e.path.split(Platform.pathSeparator).last).toList();
    }
    dynamic fileFolders = await fetchFilesAndFolders(folderID);
    if (fileFolders.containsKey('folders')) {
      dynamic folders = fileFolders['folders'];
      for (dynamic folder in folders) {
        await downloadFolder(folder['fld_id'].toString(), "$folderPath/${folder['name']}");
      }
    }
    if (fileFolders.containsKey('files')) {
      dynamic files = fileFolders['files'];
      for (dynamic file in files) {
        if (!localFiles.contains(file['name'])) {
          addDownloadingQueue({
            "fileCode": file['file_code'], 
            "fileName": file['name'], 
            "filePath": folderPath
          });
        }
      }
    }
  }
  
  Future<void> createFolderIfNotExists(String path) async {
    String parentDirectory = await getDownloadDirectory();
    final directory = Directory("$parentDirectory/$path");

    // Check if the directory exists
    if (await directory.exists()) {
    } else {
      // Create the directory
      await directory.create(recursive: true);
    }
  }

  Future<dynamic> fetchFilesAndFolders(fldId) async {
    final response = await getAPICall('$baseURL/folder/list?fld_id=${fldId.toString()}&sess_id=$sessionId');
    var data = jsonDecode(response.body);
    return data['result'];
  }

  Future<void> removeCloudItem(dynamic item) async {
    if(item.containsKey('file_code')) {
      String fileCode = item['file_code'].toString();
      final response = await http.get(
        Uri.parse('$baseURL/file/remove?file_code=$fileCode&remove=1&sess_id=$sessionId'),
      );
      if (response.statusCode == 200) {
      } else {
        isOffline = true;
      }
    } else {
      String folderID = item['fld_id'].toString();
      await removeFolder(folderID);
    }
  }

  Future<void> shareItem(dynamic item) async {
    if(item.containsKey('file_code')) {
      String fileCode = item['file_code'].toString();
      String shareState = (1 - item['only_me']).toString();
      final response = await http.get(
        Uri.parse('$baseURL/file/only_me?file_code=$fileCode&only_me=$shareState&sess_id=$sessionId'),
      );
      if (response.statusCode == 200) {
      } else {
        isOffline = true;
      }
    } else {
      // String folderID = item['fld_id'].toString();
      print("Only Files are able to share.");
    }
  }

  Future<void> lockItem(dynamic item, String password) async {
    if(item.containsKey('file_code')) {
      String fileCode = item['file_code'].toString();
      final response = await http.get(
        Uri.parse('$baseURL/file/set_password?file_code=$fileCode&file_password=$password&sess_id=$sessionId'),
      );
      if (response.statusCode == 200) {
      } else {
        isOffline = true;
      }
    } else {
      // String folderID = item['fld_id'].toString();
      print("Only Files are able to share.");
    }
  }

  Future<void> removeFolder(String folderID) async {
    await getAPICall('$baseURL/folder/delete?fld_id=$folderID&sess_id=$sessionId');
  }

  Future<void> renameFile(dynamic item, String newName) async {
    if (item.containsKey('file_code')) {
      String fileCode = item['file_code'].toString();
      await getAPICall('$baseURL/file/rename?file_code=$fileCode&name=$newName&sess_id=$sessionId');
    } else if (item.containsKey('fld_id')) {
      String folderID = item['fld_id'].toString();
      await getAPICall('$baseURL/folder/rename?fld_id=$folderID&name=$newName&sess_id=$sessionId');
    }
  }

  Future<void> restoreCloudItem(dynamic item) async {
    if (item.containsKey('file_code')) {
      String fileCode = item['file_code'].toString();
      await getAPICall('$baseURL/file/restore?file_code=$fileCode&restore=1&sess_id=$sessionId');
    } else if (item.containsKey('fld_id')) {
      String folderID = item['fld_id'].toString();
      await getAPICall('$baseURL/folder/restore?fld_id=$folderID&sess_id=$sessionId');
    }
  }

  Future<void> _performSync(SyncOrder order) async {
    print('perform sync');
    switch (order.syncType) {
      case "Upload Only":
        await uploadFolder(order.localPath, order.fld_id);
        break;
      case "Download Only":
        await downloadFolder(order.fld_id, order.localPath, );
        break;
      case "One-Way Sync":
        await _onewaySync(order.localPath, order.fld_id);
        break;
      case "Two-Way Sync":
        await _twowaySync(order.localPath, order.fld_id, _findFolderData(syncedFileFolders, order.fld_id));
        break;
    }
  }

  Future<dynamic> _scanCloudFiles(String folderName, String fldID) async {
    dynamic scanedData = {};
    // Update synced files.
    final response = await getAPICall('$baseURL/folder/list?fld_id=$fldID&sess_id=$sessionId');
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
    return {"folder_name": folderName, "folder_id": fldID, "folder_data": scanedData};

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
    
    final response = await getAPICall('$baseURL/folder/list?fld_id=$folderID&sess_id=$sessionId');
    var data = jsonDecode(response.body);
    cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
    cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code']));
    cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
    cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));

    for (String file in localFiles) {
      if (!cloudFiles.contains(file)) {
        String filePath = "$localPath${Platform.pathSeparator}$file";
        File uploadFile = File(filePath);
        if (uploadFile.existsSync()) {
          addUploadQueue({
            "filePath": filePath,
            "folderID": folderID,
          });
        }
      }
    }

    for (int i = 0; i < cloudFiles.length; i++) {
      String file = cloudFiles[i];
      if (!localFiles.contains(file)) {
        try {
          await http.get(Uri.parse('$baseURL/file/remove?file_code=${cloudFileCodes[i]}&remove=1&sess_id=$sessionId'));
        } catch (e) {
          isOffline = true;
        }
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
      await uploadFolder(localPath, folderID);
      await downloadFolder(localPath, folderID);
      return;
    }

    if (!folderData.containsKey('file') && !folderData.containsKey('folder')) {
      await uploadFolder(localPath, folderID);
      await downloadFolder(localPath, folderID);
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

    final response = await getAPICall('$baseURL/folder/list?fld_id=$folderID&sess_id=$sessionId');
    var data = jsonDecode(response.body);
    cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));
    cloudFileCodes = List<String>.from(data['result']['files'].map((file) => file['file_code']));
    cloudFolders = List<String>.from(data['result']['folders'].map((file) => file['name']));
    cloudFolderCodes = List<String>.from(data['result']['folders'].map((file) => file['fld_id'].toString()));

    for (int i = 0; i < cloudFiles.length; i ++) {
      String file = cloudFiles[i];
      if (!syncFiles.contains(file)) {
        addDownloadingQueue({
          "fileCode": cloudFileCodes[i], 
          "fileName": file, 
          "filePath": localPath
        });
      }
    }

    for (String file in localFiles) {
      if (!syncFiles.contains(file)) {
        String filePath = "$localPath${Platform.pathSeparator}$file";
        File uploadFile = File(filePath);
        if (uploadFile.existsSync()) {
          addUploadQueue({
            "filePath": filePath,
            "folderID": folderID,
          });
        }
      }
    }

    for (int i = 0; i < syncFiles.length; i ++) {
      String file = syncFiles[i];
      if(!localFiles.contains(file)) {
        removeCloudItem({'file_code': syncFileCodes[i]});
      }
      if(!cloudFiles.contains(file)) {
        String filePath = "$localPath${Platform.pathSeparator}$file";
        final deletefile = File(filePath);
        if (await deletefile.exists()) {
          await deletefile.delete();
        } else {
        }
      }
    }

    for (int i = 0; i < cloudFolders.length; i ++) {
      String folder = cloudFolders[i];
      String folderCode = cloudFolderCodes[i];
      if (!syncFolderNames.contains(folder)) {
        await createFolderIfNotExists("$localPath${Platform.pathSeparator}$folder");
        await downloadFolder("$localPath${Platform.pathSeparator}$folder", folderCode);
      }
    }

    for (String folder in localFolders) {
      if (!syncFolderNames.contains(folder)) {
        if (!cloudFolders.contains(folder)) {
          String newFoldeId = await createCloudFolder(folder, folderID);
          await uploadFolder("$localPath/$folder", newFoldeId);
        } else {
          await uploadFolder("$localPath/$folder", cloudFolderCodes[cloudFolders.indexOf(folder)]);
        }
      }
    }

    for (int i = 0; i < syncFolderNames.length; i ++) {
      String folder = syncFolderNames[i];
      if (!localFolders.contains(folder)) {
        await removeFolder(syncFolderCodes[i]);
      } else if (!cloudFolders.contains(folder)) {
        await _deleteLocalFolder("$localPath/$folder");
      } else {
        await _twowaySync("$localPath/$folder", syncFolderCodes[i], syncFolderDatas[i]);
      }
    }

  }

  Future<void> _deleteLocalFolder(String folderPath) async {
      // Create a Directory object
    var directory = Directory(folderPath);

    // Check if the directory exists
    if (directory.existsSync()) {
      // Delete the directory
      directory.deleteSync(recursive: true);
    } else {
    }
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

  void _startBackup() async {
    print("✅ Background Sync Started!");
    String cameraFolderID = await getFolderID("Camera", "0");
      if (cameraFolderID == "") {
        cameraFolderID = await createCloudFolder("Camera", "0");
      }
    _uploadCameraFolder(cameraFolderID);
    if (_backgroundIsolate != null) return;
    ReceivePort newReceivePort = ReceivePort();
    _backgroundIsolate = await Isolate.spawn(_fileWatcher, newReceivePort.sendPort);
    newReceivePort.listen((message) async {
      String detectedFilePath = message as String;
      // await Future.delayed(Duration(seconds: 3));
      addUploadQueue({
        "filePath": detectedFilePath,
        "folderID": cameraFolderID,
      });
    });
    print("✅ Background Sync Started!");
  }

  Future<void> _uploadCameraFolder(String cameraFolderID) async {
    bool hasPermission = await _requestStoragePermission();
    if (!hasPermission) {
      print("❌ Storage permission denied");
      return;
    }
    List<String> cloudFiles = [];
    final response = await getAPICall('$baseURL/folder/list?fld_id=$cameraFolderID&sess_id=$sessionId');
    var data = jsonDecode(response.body);
    cloudFiles = List<String>.from(data['result']['files'].map((file) => file['name']));

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
        String cameraFolderID = await getFolderID("Camera", "0");
        if (cameraFolderID == "") {
          cameraFolderID = await createCloudFolder("Camera", "0");
        }
        addUploadQueue({
          "filePath": file.path,
          'folderID': cameraFolderID
        });
        lastBackupDate = DateTime.now();
        _saveSetting("last_backup_date", lastBackupDate);
      }
    }
    print("Backup completed: ${mediaFiles.length} files uploaded");
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
              sendPort.send({'event': 'create', 'path': event.path});
            } else if (event.type == FileSystemEvent.delete) {
              sendPort.send({'event': 'delete', 'path': event.path});
            // } else if (event.type == FileSystemEvent.modify) {
            //   print("✏️ File/Folder Modified: ${event.path}");
            //   sendPort.send({'event': 'modify', 'path': event.path});
            } else if (event.type == FileSystemEvent.move) {
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
      sendPort.send({'event': 'create', 'path': event.path});
    } else if (event.type == FileSystemEvent.delete) {
      sendPort.send({'event': 'delete', 'path': event.path});
    // } else if (event.type == FileSystemEvent.modify) {
    //   sendPort.send({'event': 'modify', 'path': event.path});
    } else if (event.type == FileSystemEvent.move) {
      sendPort.send({'event': 'move', 'path': event.path});
    }
  });

  // Watch the subdirectories
  watchSubdirectories(directory);
}
