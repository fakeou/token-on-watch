import 'package:flutter/material.dart';

import '../app.dart';
import '../models/api_config.dart';
import '../models/token_usage.dart';

/// 展示模式
enum _DisplayMode {
  /// 按量计费（DeepSeek, OpenAI, Claude）：余额 + 今日费用 + 今日 tokens
  balance,
  /// 时间窗口限额（Sub2API）：日限额进度条 + 月总额进度条
  quotaWindow,
  /// 简单总量限制（Mimo, Kimi）：使用量/总量进度条 + 今日 tokens
  simpleLimit,
}

/// Token 卡片组件
/// 在主页列表中展示单个 AI 平台的 token 使用情况
class TokenCard extends StatelessWidget {
  final ApiConfig config;
  final TokenUsage? usage;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TokenCard({
    super.key,
    required this.config,
    this.usage,
    this.onTap,
    this.onLongPress,
  });

  _DisplayMode get _mode {
    if (usage == null) return _DisplayMode.simpleLimit;
    if (usage!.hasQuotaWindows) return _DisplayMode.quotaWindow;
    if (usage!.hasBalance) return _DisplayMode.balance;
    return _DisplayMode.simpleLimit;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getBorderColor(),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            if (usage != null && usage!.isActive) ...[
              _buildContent(),
            ] else if (usage == null) ...[
              _buildLoadingState(),
            ] else ...[
              _buildErrorState(),
            ],
          ],
        ),
      ),
    );
  }

  /// 根据模式渲染不同内容
  Widget _buildContent() {
    switch (_mode) {
      case _DisplayMode.balance:
        return _buildBalanceMode();
      case _DisplayMode.quotaWindow:
        return _buildQuotaWindowMode();
      case _DisplayMode.simpleLimit:
        return _buildSimpleLimitMode();
    }
  }

  // ============ 模式1：按量计费（余额模式） ============
  // 有今日数据就三列，没有就只显示余额
  Widget _buildBalanceMode() {
    final balance = usage!.balanceAmount ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildBalanceStat('余额', '${balance.toStringAsFixed(2)} ${usage!.balanceCurrency ?? ''}'),
      ],
    );
  }

  Widget _buildBalanceStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
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

  // ============ 模式2：时间窗口限额 ============
  // 首页展示：日限额进度条 + 月总额度
  Widget _buildQuotaWindowMode() {
    final dailyLimit = usage!.dailyLimit ?? 0;
    final dailyUsed = usage!.dailyUsed ?? 0;
    final monthlyLimit = usage!.monthlyLimit ?? 0;
    final monthlyUsed = usage!.monthlyUsed ?? 0;
    final remaining = usage!.balanceAmount ?? 0;

    final dailyPercent = dailyLimit > 0 ? (dailyUsed / dailyLimit).clamp(0.0, 1.0) : 0.0;
    final monthlyPercent = monthlyLimit > 0 ? (monthlyUsed / monthlyLimit).clamp(0.0, 1.0) : 0.0;

    return Column(
      children: [
        // 今日限额进度条
        _buildQuotaBar(
          label: '今日',
          used: dailyUsed,
          limit: dailyLimit,
          percent: dailyPercent,
        ),
        const SizedBox(height: 10),
        // 月限额进度条
        _buildQuotaBar(
          label: '本月',
          used: monthlyUsed,
          limit: monthlyLimit,
          percent: monthlyPercent,
        ),
        const SizedBox(height: 8),
        // 底部：剩余额度
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              '剩余额度 ',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            Text(
              '\$${remaining.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuotaBar({
    required String label,
    required double used,
    required double limit,
    required double percent,
  }) {
    final color = _getProgressColor(percent);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            Text(
              '\$${used.toStringAsFixed(2)} / \$${limit.toStringAsFixed(0)}',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  // ============ 模式3：简单总量限制 ============
  // 展示：使用量/总量进度条
  Widget _buildSimpleLimitMode() {
    final percent = usage!.usagePercent;
    final color = _getProgressColor(percent);

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '已用 ${usage!.tokensUsedFormatted}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            Text(
              usage!.usagePercentText,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '剩余 ${usage!.tokensRemainingFormatted}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 头部区域
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              config.sourceIcon,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                config.name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                usage?.name ?? config.sourceDisplayName,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        _buildStatusBadge(),
      ],
    );
  }

  Widget _buildStatusBadge() {
    final color = _getStatusColor();
    final text = _getStatusText();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 8),
          Text(
            '加载中...',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: 6),
          Text(
            usage!.status == 'expired' ? '已过期' : '连接异常',
            style: TextStyle(
              color: usage!.status == 'expired'
                  ? AppColors.warning
                  : AppColors.danger,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Color _getBorderColor() {
    if (!config.enabled) return AppColors.divider;
    if (usage == null) return AppColors.divider;
    return _getStatusColor().withOpacity(0.3);
  }

  Color _getStatusColor() {
    if (!config.enabled) return AppColors.textSecondary;
    switch (usage?.status) {
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
    if (!config.enabled) return '已禁用';
    switch (usage?.status) {
      case 'active':
        return '正常';
      case 'expired':
        return '过期';
      case 'error':
        return '异常';
      default:
        return '未知';
    }
  }

  Color _getProgressColor(double percent) {
    if (percent < 0.5) return AppColors.success;
    if (percent < 0.8) return AppColors.warning;
    return AppColors.danger;
  }
}
