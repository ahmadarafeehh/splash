import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:Ratedly/screens/post_view_screen.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController searchController = TextEditingController();

  bool isShowUsers = false;
  bool _isSearchFocused = false;
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final FirestoreBlockMethods _blockMethods = FirestoreBlockMethods();
  bool _isNavigating = false;

  List<QueryDocumentSnapshot> _allPosts = [];
  Set<String> blockedUsersSet = {};
  Map<String, bool> userPrivacyMap = {};
  bool _isLoading = true;

  // Pagination helpers:
  DocumentSnapshot? _lastPostDocument;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  final int _postsLimit = 20;

  // Scroll controller for the posts grid
  final ScrollController _scrollController = ScrollController();

  // For suggested users rotation
  List<String> _rotatedSuggestedUsers = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initData();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 300 &&
          !_isLoadingMore &&
          _hasMorePosts &&
          !isShowUsers) {
        _loadMorePosts();
      }
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    await _loadBlockedUsers();
    await _fetchPosts();
    await _loadUsersPrivacy();
    _rotateSuggestedUsers();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadBlockedUsers() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .get();
    blockedUsersSet = Set<String>.from(userDoc.data()?['blockedUsers'] ?? []);
  }

  Future<void> _fetchPosts() async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('posts')
        .orderBy(FieldPath.documentId)
        .limit(_postsLimit);

    final querySnapshot = await query.get();

    if (querySnapshot.docs.isNotEmpty) {
      _lastPostDocument = querySnapshot.docs.last;
    }

    _allPosts = querySnapshot.docs;
    _hasMorePosts = querySnapshot.docs.length == _postsLimit;
  }

  Future<void> _loadMorePosts() async {
    if (_lastPostDocument == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('posts')
        .orderBy(FieldPath.documentId)
        .startAfterDocument(_lastPostDocument!)
        .limit(_postsLimit);

    final querySnapshot = await query.get();

    if (querySnapshot.docs.isNotEmpty) {
      _lastPostDocument = querySnapshot.docs.last;
      _allPosts.addAll(querySnapshot.docs);
    }

    if (querySnapshot.docs.length < _postsLimit) {
      _hasMorePosts = false;
    }

    // Reload privacy info only for new users
    await _loadUsersPrivacy();

    setState(() {
      _isLoadingMore = false;
    });
  }

  Future<void> _loadUsersPrivacy() async {
    final userIds = _allPosts
        .map((doc) => (doc.data() as Map<String, dynamic>)['uid']?.toString())
        .whereType<String>()
        .toSet();

    final unknownIds =
        userIds.where((id) => !userPrivacyMap.containsKey(id)).toList();

    if (unknownIds.isEmpty) return;

    const batchSize = 10;

    for (int i = 0; i < unknownIds.length; i += batchSize) {
      final batchIds = unknownIds.sublist(
          i,
          i + batchSize > unknownIds.length
              ? unknownIds.length
              : i + batchSize);
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batchIds)
          .get();

      for (final userDoc in usersSnapshot.docs) {
        userPrivacyMap[userDoc.id] = userDoc.data()['isPrivate'] ?? false;
      }
    }
  }

  List<QueryDocumentSnapshot> get _filteredPosts {
    return _allPosts.where((postDoc) {
      final post = postDoc.data() as Map<String, dynamic>? ?? {};
      final postUserId = post['uid']?.toString() ?? '';

      if (postUserId.isEmpty) return false;
      if (postUserId == currentUserId) return false;
      if (blockedUsersSet.contains(postUserId)) return false;
      if (userPrivacyMap[postUserId] ?? false) return false;

      return true;
    }).toList();
  }

  /// Helper function to get the next lexicographical string after [str]
  String getNextString(String str) {
    if (str.isEmpty) return str;
    final lastChar = str.codeUnitAt(str.length - 1);
    final prefix = str.substring(0, str.length - 1);
    final nextChar = String.fromCharCode(lastChar + 1);
    return prefix + nextChar;
  }

  /// Shuffle and pick up to 5 users for suggested users so they rotate.
  void _rotateSuggestedUsers() {
    final suggestedUsers = _filteredPosts
        .map((postDoc) =>
            (postDoc.data() as Map<String, dynamic>)['uid']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    if (suggestedUsers.isEmpty) {
      _rotatedSuggestedUsers = [];
      return;
    }

    // Shuffle the list to get different users each time
    suggestedUsers.shuffle(_random);

    // Pick first 5 (or less)
    _rotatedSuggestedUsers = suggestedUsers.take(5).toList();
  }

  void _navigateToProfile(String uid) async {
    print("[NAVIGATE] Attempting to navigate to user: \$uid");
    _isNavigating = true;

    await Future.delayed(const Duration(milliseconds: 100));

    print("[NAVIGATE] Unfocused search, pushing route...");
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfileScreen(uid: uid)),
    );

    print("[NAVIGATE] Returned from profile screen");
    if (!mounted) return;

    setState(() {
      _isNavigating = false;
      isShowUsers = false;
      searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFd9d9d9)))
          : _isSearchFocused && searchController.text.trim().isEmpty
              ? Padding(
                  // Add this padding
                  padding: const EdgeInsets.only(top: 15.0),
                  child: _buildSuggestedUsers(),
                )
              : isShowUsers
                  ? Padding(
                      // Add this padding
                      padding: const EdgeInsets.only(top: 15.0),
                      child: _buildUserSearch(),
                    )
                  : _buildPostsGrid(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        toolbarHeight: 80, // make the AppBar taller
        elevation: 0, // optional: remove shadow
        iconTheme: const IconThemeData(
          color: Color(0xFFd9d9d9),
        ),
        title: Padding(
          padding: const EdgeInsets.only(
              top: 8.0), // nudge down for perfect centering
          child: SizedBox(
            height: 48, // lock the TextField height
            child: TextFormField(
              controller: searchController,
              style: const TextStyle(color: Color(0xFFd9d9d9)),
              decoration: const InputDecoration(
                hintText: 'Search for a user...',
                hintStyle: TextStyle(color: Color(0xFF666666)),
                filled: true,
                fillColor: Color(0xFF121212), // match AppBar background
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF333333)),
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFd9d9d9), width: 2),
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              onTap: () {
                if (searchController.text.trim().isEmpty) {
                  setState(() {
                    isShowUsers = false;
                    _isSearchFocused = true;
                  });
                }
              },
              onChanged: (value) {
                setState(() {
                  isShowUsers = value.trim().isNotEmpty;
                  _isSearchFocused = false;
                });
              },
              onFieldSubmitted: (_) {
                setState(() {
                  isShowUsers = true;
                  _isSearchFocused = false;
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedUsers() {
    if (_rotatedSuggestedUsers.isEmpty) {
      return const Center(
        child: Text('No suggestions available.',
            style: TextStyle(color: Color(0xFFd9d9d9))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(12.0),
          child: Text(
            'Suggested users',
            style: TextStyle(
                color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('users')
                .where(FieldPath.documentId, whereIn: _rotatedSuggestedUsers)
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFd9d9d9)));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                    child: Text('No suggestions found.',
                        style: TextStyle(color: Color(0xFFd9d9d9))));
              }
              final users = snapshot.data!.docs.where((userDoc) {
                final userId = userDoc.id;
                return !blockedUsersSet.contains(userId);
              }).toList();

              if (users.isEmpty) {
                return const Center(
                    child: Text('No suggestions found.',
                        style: TextStyle(color: Color(0xFFd9d9d9))));
              }

              return ListView.builder(
                padding: const EdgeInsets.only(top: 8),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index].data();
                  final userId = users[index].id;
                  return InkWell(
                    onTap: () => _navigateToProfile(userId),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF333333),
                          backgroundImage: (user['photoUrl'] != null &&
                                  user['photoUrl'] != "default")
                              ? NetworkImage(user['photoUrl'])
                              : null,
                          radius: 20,
                          child: (user['photoUrl'] == null ||
                                  user['photoUrl'] == "default")
                              ? const Icon(Icons.account_circle,
                                  size: 40, color: Color(0xFFd9d9d9))
                              : null,
                        ),
                        title: Text(
                          user['username']?.toString() ?? 'Unknown',
                          style: const TextStyle(color: Color(0xFFd9d9d9)),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserSearch() {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      return const Center(
          child: Text('Please enter a username.',
              style: TextStyle(color: Color(0xFFd9d9d9))));
    }
    final nextQuery = getNextString(query);

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: query)
          .where('username', isLessThan: nextQuery)
          .limit(15)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFd9d9d9)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Text('No users found.',
                  style: TextStyle(color: Color(0xFFd9d9d9))));
        }
        final users = snapshot.data!.docs.where((userDoc) {
          final userId = userDoc.id;
          return !blockedUsersSet.contains(userId);
        }).toList();

        if (users.isEmpty) {
          return const Center(
              child: Text('No users found.',
                  style: TextStyle(color: Color(0xFFd9d9d9))));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index].data();
            final userId = users[index].id;
            return InkWell(
              onTap: () => _navigateToProfile(userId),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF333333),
                    backgroundImage: (user['photoUrl'] != null &&
                            user['photoUrl'] != "default")
                        ? NetworkImage(user['photoUrl'])
                        : null,
                    radius: 20,
                    child: (user['photoUrl'] == null ||
                            user['photoUrl'] == "default")
                        ? const Icon(Icons.account_circle,
                            size: 40, color: Color(0xFFd9d9d9))
                        : null,
                  ),
                  title: Text(
                    user['username']?.toString() ?? 'Unknown',
                    style: const TextStyle(color: Color(0xFFd9d9d9)),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPostsGrid() {
    final posts = _filteredPosts;

    if (posts.isEmpty) {
      return const Center(
          child: Text('No posts found.',
              style: TextStyle(color: Color(0xFFd9d9d9))));
    }

    return Stack(
      children: [
        GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1,
            crossAxisSpacing: 8.0,
            mainAxisSpacing: 8.0,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final postDoc = posts[index];
            final post = postDoc.data() as Map<String, dynamic>? ?? {};
            final postUrl = post['postUrl']?.toString() ?? '';

            return InkWell(
              onTap: () async {
                final userSnapshot = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(post['uid'])
                    .get();
                final userData = userSnapshot.data() ?? {};

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ImageViewScreen(
                      imageUrl: postUrl,
                      postId: postDoc.id,
                      description: post['description']?.toString() ?? '',
                      userId: post['uid']?.toString() ?? '',
                      username: userData['username']?.toString() ?? '',
                      profImage: userData['photoUrl']?.toString() ?? '',
                    ),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.hardEdge,
                child: postUrl.isNotEmpty
                    ? Image.network(
                        postUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFd9d9d9)),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: const Color(0xFF333333),
                            child: const Icon(Icons.error, color: Colors.red),
                          );
                        },
                      )
                    : const Icon(Icons.broken_image, color: Color(0xFFd9d9d9)),
              ),
            );
          },
        ),
        if (_isLoadingMore)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF222222).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const CircularProgressIndicator(
                  color: Color(0xFFd9d9d9),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
