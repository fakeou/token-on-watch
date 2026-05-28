import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../models/token_usage.dart';

/// 展示模式（与 TokenCard 一致）
enum _DisplayMode {
  balance,
  quotaWindow,
  simpleLimit,
}

/// 账户详情页
/// 展示单个 AI 平台的 token 使用详情
class AccountDetailScreen extends StatelessWidget {
  final TokenUsage usage;

  const AccountDetailScreen({super.key, required this.usage});

  _DisplayMode get _mode {
    if (usage.hasQuotaWindows) return _DisplayMode.quotaWindow;
    if (usage.hasBalance) return _DisplayMode.balance;
    return _DisplayMode.simpleLimit;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(usage.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 状态卡片
            _buildStatusCard(),
            const SizedBox(height: 16),

            // 根据模式渲染不同内容
            ..._buildModeContent(),

            const SizedBox(height: 24),

            // 最后更新时间
            Center(
              child: Text(
                '最后更新: ${_formatDateTime(usage.updatedAt)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 根据模式构建不同的详情内容
  List<Widget> _buildModeContent() {
    switch (_mode) {
      case _DisplayMode.balance:
        return _buildBalanceModeContent();
      case _DisplayMode.quotaWindow:
        return _buildQuotaWindowModeContent();
      case _DisplayMode.simpleLimit:
        return _buildSimpleLimitModeContent();
    }
  }

  // ============ 模式1：按量计费 ============
  List<Widget> _buildBalanceModeContent() {
    final balance = usage.balanceAmount ?? 0;
    return [
      // 余额大数字
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text(
              '账户余额',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${balance.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (usage.balanceCurrency != null) ...[
              const SizedBox(height: 4),
              Text(
                usage.balanceCurrency!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      // 详细信息
      _buildDetailSection(),
    ];
  }

  // ============ 模式2：时间窗口限额 ============
  // 展示日/周/月三个限额进度条
  List<Widget> _buildQuotaWindowModeContent() {
    final remaining = usage.balanceAmount ?? 0;
    return [
      // 剩余额度概览
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text(
              '剩余额度',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${remaining.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      // 日/周/月限额
      if (usage.dailyLimit != null) ...[
        _buildQuotaWindowCard(
          title: '每日限额',
          icon: Icons.today,
          limit: usage.dailyLimit!,
          used: usage.dailyUsed ?? 0,
        ),
        const SizedBox(height: 12),
      ],
      if (usage.weeklyLimit != null) ...[
        _buildQuotaWindowCard(
          title: '每周限额',
          icon: Icons.view_week,
          limit: usage.weeklyLimit!,
          used: usage.weeklyUsed ?? 0,
        ),
        const SizedBox(height: 12),
      ],
      if (usage.monthlyLimit != null) ...[
        _buildQuotaWindowCard(
          title: '每月限额',
          icon: Icons.calendar_month,
          limit: usage.monthlyLimit!,
          used: usage.monthlyUsed ?? 0,
        ),
      ],
    ];
  }

  Widget _buildQuotaWindowCard({
    required String title,
    required IconData icon,
    required double limit,
    required double used,
  }) {
    final percent = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final color = _getProgressColor(percent);
    final remaining = (limit - used).clamp(0.0, limit);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '\$${used.toStringAsFixed(2)} / \$${limit.toStringAsFixed(0)}',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          // 底部统计
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '已用 \$${used.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              Text(
                '剩余 \$${remaining.toStringAsFixed(2)}',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============ 模式3：简单总量限制 ============
  List<Widget> _buildSimpleLimitModeContent() {
    final percent = usage.usagePercent;
    final color = _getProgressColor(percent);

    return [
      // 使用进度
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '使用进度',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  usage.usagePercentText,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem('已使用', usage.tokensUsedFormatted, AppColors.textSecondary),
                _buildStatItem('剩余额度', usage.tokensRemainingFormatted, color),
                _buildStatItem('总额度', usage.tokensLimitFormatted, AppColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      // 余额信息（如果有）
      if (usage.hasBalance) ...[
        _buildBalanceSection(),
        const SizedBox(height: 16),
      ],
      // 详细信息
      _buildDetailSection(),
    ];
  }

  // ============ 通用组件 ============

  Widget _buildStatusCard() {
    final statusColor = _getStatusColor();
    final statusText = _getStatusText();
    final statusIcon = _getStatusIcon();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usage.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            usage.source.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '详细信息',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildDetailRow('平台标识', usage.source),
          _buildDetailRow('配置 ID', usage.id),
          if (usage.tokensUsed > 0)
            _buildDetailRow('Token 已用', usage.tokensUsed.toString()),
          if (usage.tokensLimit > 0)
            _buildDetailRow('Token 总量', usage.tokensLimit.toString()),
          if (usage.tokensRemaining > 0)
            _buildDetailRow('Token 剩余', usage.tokensRemaining.toString()),
        ],
      ),
    );
  }

  Widget _buildBalanceSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '余额信息',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildDetailRow('余额', usage.balanceText),
          _buildDetailRow('货币', usage.balanceCurrency ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (usage.status) {
      case 'active':
        return AppColors.success;
      case 'expired':
        return AppColors.warning;
      case 'error':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getStatusText() {
    switch (usage.status) {
      case 'active':
        return '正常使用中';
      case 'expired':
        return '已过期';
      case 'error':
        return '连接异常';
      default:
        return '未知状态';
    }
  }

  IconData _getStatusIcon() {
    switch (usage.status) {
      case 'active':
        return Icons.check_circle;
      case 'expired':
        return Icons.access_time;
      case 'error':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  Color _getProgressColor(double percent) {
    if (percent < 0.5) return AppColors.success;
    if (percent < 0.8) return AppColors.warning;
    return AppColors.danger;
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }
}
