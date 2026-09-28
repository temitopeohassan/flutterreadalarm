import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Navy top bar used on the Home and Set Alarm screens.
class NavyHeader extends StatelessWidget {
  const NavyHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.titleSize = 22,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              SizedBox(width: 64, child: Center(child: leading)),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 64, child: Center(child: trailing)),
            ],
          ),
        ),
      ),
    );
  }
}
