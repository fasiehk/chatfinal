import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Import Google Maps
import 'package:video_player/video_player.dart'; // Import video_player
import 'login_page.dart';
import 'dart:async'; // Import for live location functionality

class ChatPage extends StatefulWidget {
  final String userId;
  final String userName;

  const ChatPage({super.key, required this.userId, required this.userName});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController(); // Add ScrollController
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  StreamSubscription<Position>? _liveLocationSubscription;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _fetchUserEmail();
    // Scroll to the bottom after a short delay to ensure messages are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _fetchUserEmail() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (doc.exists) {
        setState(() {
          _userEmail = doc.data()?['email'];
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch user email: $e')),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose(); // Dispose the ScrollController
    _liveLocationSubscription?.cancel(); // Cancel live location updates
    super.dispose();
  }

  Future<void> _sendMessage({String? text, String? mediaUrl, String? mediaType, Map<String, double>? location}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || (text == null && mediaUrl == null && location == null)) return;

    await _firestore.collection('messages').add({
      'senderId': currentUser.uid,
      'receiverId': widget.userId,
      'message': text,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'location': location,
      'timestamp': FieldValue.serverTimestamp(),
      'participants': [currentUser.uid, widget.userId], // Ensure both sender and receiver are included
    });
  }

  Future<void> _pickMedia(String type) async {
    try {
      // Request storage permission
      if (await Permission.storage.request().isDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission is required to pick media.')),
        );
        return;
      }

      final picker = ImagePicker();
      XFile? pickedFile;

      if (type == 'image') {
        pickedFile = await picker.pickImage(source: ImageSource.gallery);
      } else if (type == 'video') {
        pickedFile = await picker.pickVideo(source: ImageSource.gallery);
      }

      if (pickedFile != null) {
        final fileBytes = await pickedFile.readAsBytes();
        final fileName = DateTime.now().millisecondsSinceEpoch.toString();
        final ref = _storage.ref().child('media/$fileName');

        await ref.putData(fileBytes);
        final mediaUrl = await ref.getDownloadURL();

        _sendMessage(mediaUrl: mediaUrl, mediaType: type);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick media: $e')),
      );
    }
  }

  Future<void> _sendLocation() async {
    try {
      // Request location permission
      if (await Permission.location.request().isDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to send location.')),
        );
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled. Please enable them.')),
        );
        return;
      }

      // Show dialog to ask for current or live location
      final selectedOption = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Send Location'),
            content: const Text('Do you want to send your current location or share live location?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'current'),
                child: const Text('Current Location'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'live'),
                child: const Text('Live Location'),
              ),
            ],
          );
        },
      );

      if (selectedOption == 'current') {
        // Send current location
        final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        _sendMessage(
          location: {'latitude': position.latitude, 'longitude': position.longitude},
          mediaType: 'location',
        );
      } else if (selectedOption == 'live') {
        // Send live location
        _startLiveLocation();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send location: $e')),
      );
    }
  }

  void _startLiveLocation() {
    _liveLocationSubscription?.cancel(); // Cancel any existing subscription
    int updateCount = 0; // Counter to track the number of updates

    _liveLocationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((Position position) {
      if (updateCount < 6) {
        _sendMessage(
          location: {'latitude': position.latitude, 'longitude': position.longitude},
          mediaType: 'location',
        );
        updateCount++; // Increment the counter
      } else {
        _liveLocationSubscription?.cancel(); // Stop updates after 6 times
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live location sharing stopped after 6 updates.')),
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Live location sharing started.')),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Widget _buildMessageWidget(Map<String, dynamic> message, bool isMe) {
    final double containerWidth = MediaQuery.of(context).size.width * 0.6; // Set a fixed width for media containers

    if (message['mediaType'] == 'image') {
      return SizedBox(
        width: containerWidth,
        child: Image.network(
          message['mediaUrl'] ?? '',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Text('Failed to load image'),
        ),
      );
    } else if (message['mediaType'] == 'video') {
      return SizedBox(
        width: containerWidth,
        child: VideoPlayerWidget(videoUrl: message['mediaUrl'], isSender: isMe),
      );
    } else if (message['mediaType'] == 'location') {
      final location = message['location'];
      return SizedBox(
        width: containerWidth,
        height: 200,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(location['latitude'], location['longitude']),
            zoom: 14,
          ),
          markers: {
            Marker(
              markerId: const MarkerId('shared_location'),
              position: LatLng(location['latitude'], location['longitude']),
            ),
          },
        ),
      );
    } else {
      return Text(message['message'] ?? '');
    }
  }

  Stream<QuerySnapshot> _getMessages() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return const Stream.empty();

    return _firestore
        .collection('messages')
        .where('participants', arrayContains: currentUser.uid) // Ensure messages are filtered for both sender and receiver
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.userName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (_userEmail != null)
              Text(
                _userEmail!,
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getMessages(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final messages = snapshot.data?.docs ?? [];
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom()); // Scroll to bottom when messages update
                return ListView.builder(
                  controller: _scrollController, // Attach ScrollController
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index].data() as Map<String, dynamic>;
                    final isMe = message['senderId'] == _auth.currentUser?.uid;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.deepPurple : Colors.grey[300],
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                            bottomRight: isMe ? Radius.zero : const Radius.circular(12),
                          ),
                        ),
                        child: _buildMessageWidget(message, isMe),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image, color: Colors.deepPurple),
                  onPressed: () => _pickMedia('image'),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam, color: Colors.deepPurple),
                  onPressed: () => _pickMedia('video'),
                ),
                IconButton(
                  icon: const Icon(Icons.location_on, color: Colors.deepPurple),
                  onPressed: _sendLocation,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      filled: true,
                      fillColor: Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.deepPurple),
                  onPressed: () => _sendMessage(text: _messageController.text.trim()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final bool isSender; // Add a flag to indicate if the message is from the sender

  const VideoPlayerWidget({super.key, required this.videoUrl, required this.isSender});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isPlaying = false; // Start with the video paused
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {}); // Ensure the UI updates after initialization
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  void _setVolume(double volume) {
    setState(() {
      _volume = volume;
      _controller.setVolume(volume);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? Column(
            mainAxisSize: MainAxisSize.min, // Ensure the column doesn't overflow
            children: [
              AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: widget.isSender ? Colors.black : Colors.deepPurple, // Adjust color based on sender/receiver
                      ),
                      onPressed: _togglePlayPause,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          const Text("Volume:", style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: _volume,
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              onChanged: _setVolume,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        : const Center(child: CircularProgressIndicator());
  }
}
