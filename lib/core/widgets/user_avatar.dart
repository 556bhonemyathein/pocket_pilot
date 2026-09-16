import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../extensions/extensions.dart';

/// Renders a circular user avatar from a local file path, a remote URL, or
/// falls back gracefully to the user's initials.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.avatarUrl, this.name, this.radius = 24, this.heroTag, this.backgroundColor, this.foregroundColor});

  final String? avatarUrl;
  final String? name;
  final double radius;
  final String? heroTag;
  final Color? backgroundColor;
  final Color? foregroundColor;

  static bool isNetworkUrl(String url) {
    final lower = url.toLowerCase().trim();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    final String? url = avatarUrl?.trim();

    if (url != null && url.isNotEmpty) {
      if (isNetworkUrl(url)) {
        content = ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            height: radius * 2,
            width: radius * 2,
            fit: BoxFit.cover,
            placeholder: (_, _) => _placeholder(context),
            errorWidget: (_, _, _) => _fallback(context),
          ),
        );
      } else {
        final File file = File(url);
        content = ClipOval(
          child: Image.file(file, height: radius * 2, width: radius * 2, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallback(context)),
        );
      }
    } else {
      content = _fallback(context);
    }

    if (heroTag != null) {
      return Hero(tag: heroTag!, child: content);
    }
    return content;
  }

  Widget _placeholder(BuildContext context) {
    return CircleAvatar(radius: radius, backgroundColor: backgroundColor ?? context.colors.primaryContainer);
  }

  Widget _fallback(BuildContext context) {
    final String initials = (name ?? '').initials;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? context.colors.primaryContainer,
      child: Text(
        initials,
        style: TextStyle(fontSize: radius * 0.72, fontWeight: FontWeight.w600, color: foregroundColor ?? context.colors.onPrimaryContainer),
      ),
    );
  }
}
