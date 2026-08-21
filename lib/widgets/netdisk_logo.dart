import 'package:flutter/material.dart';

/// 网盘品牌标识。这里用一个枚举统一指代三种接入的网盘，
/// 方便在「网盘」首页与「我的」页复用官方彩色 logo。
enum NetdiskProvider { quark, xunlei, netdisk123 }

/// 官方彩色 logo 展示组件：白底图 + 圆角裁切。
/// 白色背景通过叠加一层白色打底，避免透明底 logo 透出卡片底色。
class NetdiskLogo extends StatelessWidget {
  final NetdiskProvider provider;
  final double size;
  final double radius;

  const NetdiskLogo({
    super.key,
    required this.provider,
    this.size = 40,
    this.radius = 12,
  });

  String get _asset {
    switch (provider) {
      case NetdiskProvider.quark:
        return 'assets/icons/quark.png';
      case NetdiskProvider.xunlei:
        return 'assets/icons/xunlei.png';
      case NetdiskProvider.netdisk123:
        return 'assets/icons/netdisk123.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          _asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}