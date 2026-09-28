import 'package:flutter/material.dart';
import '../models/reading_alarm.dart';
import '../theme/app_colors.dart';

/// Placeholder cover: gradient + title. Swap for Image.file(coverPath)
/// once covers are extracted from EPUB metadata / PDF page 1.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.width = 52});

  final BookInfo book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.42;
    final light = book.coverColors.first.computeLuminance() > 0.5;

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(width * 0.1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: book.coverColors,
        ),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: Offset(1, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        book.title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.fade,
        style: TextStyle(
          fontSize: width * 0.15,
          height: 1.15,
          fontWeight: FontWeight.w600,
          color: light ? AppColors.orangeDark : Colors.white,
        ),
      ),
    );
  }
}
