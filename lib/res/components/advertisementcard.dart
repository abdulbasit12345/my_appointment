import 'package:flutter/material.dart';

Widget advertisementCard(
    {required String imageUrl,
    required String title,
    required String description}) {
  return Card(
    margin: const EdgeInsets.all(10),
    child: SizedBox(
      width: 300, // Adjust the width according to your preference
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 100, // Adjust the height according to your preference
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
