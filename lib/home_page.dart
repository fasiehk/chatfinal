import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Future<List<Map<String, dynamic>>> _getChats() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return [];

    final querySnapshot = await _firestore
        .collection('messages')
        .where('participants', arrayContains: currentUser.uid)
        .orderBy('timestamp', descending: true)
        .get();

    final chats = <String, dynamic>{};
    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      final otherUserId = (data['participants'] as List).firstWhere((id) => id != currentUser.uid);
      if (!chats.containsKey(otherUserId)) {
        chats[otherUserId] = data;
      }
    }

    return chats.entries
        .map((entry) => {'userId': entry.key, 'lastMessage': entry.value})
        .toList();
  }

  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    if (query.isEmpty) return [];
    final querySnapshot = await _firestore
        .collection('users')
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: query + '\uf8ff')
        .get();

    return querySnapshot.docs.map((doc) => doc.data()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _auth.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value.trim()),
              decoration: InputDecoration(
                hintText: 'Search users or chats...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _searchQuery.isEmpty
                ? FutureBuilder<List<Map<String, dynamic>>>(
                    future: _getChats(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      final chats = snapshot.data ?? [];
                      if (chats.isEmpty) {
                        return const Center(child: Text('No chats found.'));
                      }

                      return ListView.builder(
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          final lastMessage = chat['lastMessage'];
                          final userId = chat['userId'];

                          return FutureBuilder<DocumentSnapshot>(
                            future: _firestore.collection('users').doc(userId).get(),
                            builder: (context, userSnapshot) {
                              if (userSnapshot.connectionState == ConnectionState.waiting) {
                                return const ListTile(title: Text('Loading...'));
                              }
                              if (userSnapshot.hasError || !userSnapshot.hasData) {
                                return const ListTile(title: Text('Error loading user'));
                              }

                              final user = userSnapshot.data!.data() as Map<String, dynamic>;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.deepPurple,
                                  child: Text(user['name'][0].toUpperCase()),
                                ),
                                title: Text(user['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  lastMessage['message'] ?? 'Media',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChatPage(
                                        userId: userId,
                                        userName: user['name'],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  )
                : FutureBuilder<List<Map<String, dynamic>>>(
                    future: _searchUsers(_searchQuery),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      final users = snapshot.data ?? [];
                      if (users.isEmpty) {
                        return const Center(child: Text('No users found.'));
                      }

                      return ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.deepPurple,
                              child: Text(user['name'][0].toUpperCase()),
                            ),
                            title: Text(user['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatPage(
                                    userId: user['id'],
                                    userName: user['name'],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
