import 'package:flutter/material.dart';

import '../app.dart';

/// 状态指示器组件
/// 在 AppBar 中显示手表连接状态
class StatusIndicator extends StatelessWidget {
  /// 是否已连接
  final bool connected;

  /// 点击回调（用于手动刷新连接状态）
  final VoidCallback? onTap;

  const StatusIndicator({
    super.key,
    required this.connected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: (connected ? AppColors.success : AppColors.danger)
              .withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (connected ? AppColors.success : AppColors.danger)
                .withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 连接指示灯
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: connected ? AppColors.success : AppColors.danger,
                shape: BoxShape.circle,
                boxShadow: connected
                    ? [
                        BoxShadow(
                          color: AppColors.success.withOpacity(0.5),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            // 连接文本
            Text(
              connected ? '手表已连接' : '手表未连接',
              style: TextStyle(
                color: connected ? AppColors.success : AppColors.danger,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
