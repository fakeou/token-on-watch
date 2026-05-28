/**
 * models.js - 数据模型层
 *
 * 适配手机端三种 Token 展示方式：
 * 1. Token 用量模式 - tokensUsed / tokensLimit / tokensRemaining
 * 2. 货币余额模式 - balanceAmount / balanceCurrency
 * 3. 限额窗口模式 - daily/weekly/monthly Limit/Used (Sub2API 专用)
 */

/**
 * 平台配置映射
 */
export const PLATFORM_CONFIG = {
  deepseek: { name: 'DeepSeek', icon: '🔮', hasBalance: true },
  kimi: { name: 'Kimi', icon: '🌙', hasBalance: false },
  mimo: { name: '小米 Mimo', icon: '📱', hasBalance: false },
  newapi: { name: 'NewAPI', icon: '🆕', hasBalance: true },
  sub2api: { name: 'Sub2API', icon: '🔄', hasBalance: true, hasQuota: true },
  openai: { name: 'OpenAI', icon: '🤖', hasBalance: false },
  claude: { name: 'Claude', icon: '🧠', hasBalance: false },
  relay: { name: '中转站', icon: '🔄', hasBalance: true }
}

/**
 * 展示模式枚举
 */
export const DisplayMode = {
  TOKEN_USAGE: 'token_usage',    // Token 用量模式
  BALANCE: 'balance',            // 货币余额模式
  QUOTA_WINDOW: 'quota_window'   // 限额窗口模式
}

/**
 * 状态枚举
 */
export const Status = {
  ACTIVE: 'active',
  EXPIRED: 'expired',
  ERROR: 'error'
}

/**
 * Token 数据模型
 * 统一适配三种展示方式
 */
export class TokenData {
  /**
   * @param {Object} raw - 原始数据（来自手机端）
   */
  constructor(raw = {}) {
    // 基础信息
    this.id = raw.id || ''
    this.source = raw.source || ''
    this.name = raw.name || ''
    this.status = raw.status || Status.ACTIVE
    this.updatedAt = raw.updated_at || raw.updatedAt || Date.now()

    // Token 用量
    const tokens = raw.tokens || {}
    this.tokensUsed = tokens.used || raw.tokensUsed || 0
    this.tokensLimit = tokens.limit || raw.tokensLimit || 0
    this.tokensRemaining = tokens.remaining || raw.tokensRemaining || 0
    this.tokensUnit = tokens.unit || 'tokens'

    // 货币余额
    const balance = raw.balance || {}
    this.balanceAmount = balance.amount ?? raw.balanceAmount ?? null
    this.balanceCurrency = balance.currency || raw.balanceCurrency || null

    // 计费周期
    const billing = raw.billing || {}
    this.periodStart = billing.period_start || raw.periodStart || null
    this.periodEnd = billing.period_end || raw.periodEnd || null

    // 限额窗口 (Sub2API 专用)
    this.dailyLimit = raw.dailyLimit || null
    this.dailyUsed = raw.dailyUsed || null
    this.weeklyLimit = raw.weeklyLimit || null
    this.weeklyUsed = raw.weeklyUsed || null
    this.monthlyLimit = raw.monthlyLimit || null
    this.monthlyUsed = raw.monthlyUsed || null

    // 错误信息（如果有）
    this.errorCode = raw.errorCode || null
    this.errorMessage = raw.errorMessage || null
  }

  /**
   * 获取平台配置
   */
  get platformConfig() {
    return PLATFORM_CONFIG[this.source] || { name: this.source, icon: '❓', hasBalance: false }
  }

  /**
   * 获取显示名称
   */
  get displayName() {
    return this.name || this.platformConfig.name
  }

  /**
   * 获取平台图标
   */
  get icon() {
    return this.platformConfig.icon
  }

  /**
   * 判断展示模式
   * @returns {string} DisplayMode
   */
  get displayMode() {
    // 优先判断限额窗口模式
    if (this.hasQuotaWindows) {
      return DisplayMode.QUOTA_WINDOW
    }
    // 判断货币余额模式
    if (this.hasBalance) {
      return DisplayMode.BALANCE
    }
    // 默认 Token 用量模式
    return DisplayMode.TOKEN_USAGE
  }

  /**
   * 是否有货币余额
   */
  get hasBalance() {
    return this.balanceAmount !== null && this.balanceCurrency !== null
  }

  /**
   * 是否有限额窗口数据
   */
  get hasQuotaWindows() {
    return this.dailyLimit !== null || this.weeklyLimit !== null || this.monthlyLimit !== null
  }

  /**
   * 是否为活跃状态
   */
  get isActive() {
    return this.status === Status.ACTIVE
  }

  /**
   * 是否有错误
   */
  get isError() {
    return this.status === Status.ERROR || this.errorCode !== null
  }

  /**
   * Token 使用百分比 (0-100)
   */
  get usagePercent() {
    if (this.tokensLimit <= 0) return 0
    return Math.min(100, Math.round((this.tokensUsed / this.tokensLimit) * 100))
  }

  /**
   * Token 剩余百分比 (0-100)
   */
  get remainingPercent() {
    if (this.tokensLimit <= 0) return 0
    return Math.min(100, Math.round((this.tokensRemaining / this.tokensLimit) * 100))
  }

  /**
   * 获取状态颜色
   */
  get statusColor() {
    if (this.isError) return '#EF5350'
    if (!this.isActive) return '#FFA726'

    // 根据展示模式判断颜色
    if (this.displayMode === DisplayMode.TOKEN_USAGE) {
      const percent = this.usagePercent
      if (percent >= 90) return '#EF5350'   // 危险
      if (percent >= 70) return '#FFA726'   // 警告
      return '#66BB6A'                       // 正常
    }

    if (this.displayMode === DisplayMode.BALANCE) {
      // 余额模式：低余额警告
      if (this.balanceAmount !== null && this.balanceAmount < 1) return '#EF5350'
      if (this.balanceAmount !== null && this.balanceAmount < 5) return '#FFA726'
      return '#66BB6A'
    }

    return '#66BB6A'
  }

  /**
   * 获取状态文本
   */
  get statusText() {
    if (this.isError) return '错误'
    if (!this.isActive) return '已过期'

    if (this.displayMode === DisplayMode.TOKEN_USAGE) {
      const percent = this.usagePercent
      if (percent >= 95) return '即将耗尽'
      if (percent >= 90) return '余量不足'
      if (percent >= 70) return '用量较高'
      return '正常'
    }

    if (this.displayMode === DisplayMode.BALANCE) {
      return `余额 ${this.balanceText}`
    }

    return '正常'
  }

  /**
   * 格式化 Token 数量
   */
  get tokensUsedFormatted() {
    return this._formatNumber(this.tokensUsed)
  }

  get tokensLimitFormatted() {
    return this._formatNumber(this.tokensLimit)
  }

  get tokensRemainingFormatted() {
    return this._formatNumber(this.tokensRemaining)
  }

  /**
   * 格式化余额
   */
  get balanceText() {
    if (!this.hasBalance) return 'N/A'
    return `${this.balanceCurrency} ${this.balanceAmount.toFixed(2)}`
  }

  /**
   * 格式化计费周期
   */
  get periodText() {
    if (!this.periodStart || !this.periodEnd) return ''
    const start = new Date(this.periodStart)
    const end = new Date(this.periodEnd)
    return `${start.getMonth() + 1}/${start.getDate()} - ${end.getMonth() + 1}/${end.getDate()}`
  }

  /**
   * 获取主要显示值（卡片中间大字）
   */
  get primaryValue() {
    if (this.displayMode === DisplayMode.TOKEN_USAGE) {
      return `${this.usagePercent}%`
    }
    if (this.displayMode === DisplayMode.BALANCE) {
      return this.balanceText
    }
    if (this.displayMode === DisplayMode.QUOTA_WINDOW) {
      // 显示月度使用率
      if (this.monthlyLimit && this.monthlyUsed !== null) {
        const percent = Math.round((this.monthlyUsed / this.monthlyLimit) * 100)
        return `${percent}%`
      }
      return 'N/A'
    }
    return 'N/A'
  }

  /**
   * 获取次要显示信息（卡片底部）
   */
  get secondaryInfo() {
    if (this.displayMode === DisplayMode.TOKEN_USAGE) {
      return `${this.tokensUsedFormatted} / ${this.tokensLimitFormatted}`
    }
    if (this.displayMode === DisplayMode.BALANCE) {
      return this.periodText || '余额模式'
    }
    if (this.displayMode === DisplayMode.QUOTA_WINDOW) {
      return '限额窗口模式'
    }
    return ''
  }

  /**
   * 获取限额窗口数据列表
   * @returns {Array<{label: string, used: number, limit: number, percent: number}>}
   */
  get quotaWindows() {
    const windows = []

    if (this.dailyLimit !== null) {
      const used = this.dailyUsed || 0
      windows.push({
        label: '日限额',
        used,
        limit: this.dailyLimit,
        percent: Math.round((used / this.dailyLimit) * 100)
      })
    }

    if (this.weeklyLimit !== null) {
      const used = this.weeklyUsed || 0
      windows.push({
        label: '周限额',
        used,
        limit: this.weeklyLimit,
        percent: Math.round((used / this.weeklyLimit) * 100)
      })
    }

    if (this.monthlyLimit !== null) {
      const used = this.monthlyUsed || 0
      windows.push({
        label: '月限额',
        used,
        limit: this.monthlyLimit,
        percent: Math.round((used / this.monthlyLimit) * 100)
      })
    }

    return windows
  }

  /**
   * 数字格式化（1.2K, 3.5M）
   */
  _formatNumber(num) {
    if (num === null || num === undefined) return '--'
    if (typeof num !== 'number' || isNaN(num)) return '--'

    if (num >= 1000000) {
      const val = num / 1000000
      return (val % 1 === 0 ? val : val.toFixed(1)) + 'M'
    }
    if (num >= 1000) {
      const val = num / 1000
      return (val % 1 === 0 ? val : val.toFixed(1)) + 'K'
    }
    return String(num)
  }

  /**
   * 转换为普通对象（用于缓存）
   */
  toObject() {
    return {
      id: this.id,
      source: this.source,
      name: this.name,
      status: this.status,
      updatedAt: this.updatedAt,
      tokensUsed: this.tokensUsed,
      tokensLimit: this.tokensLimit,
      tokensRemaining: this.tokensRemaining,
      balanceAmount: this.balanceAmount,
      balanceCurrency: this.balanceCurrency,
      periodStart: this.periodStart,
      periodEnd: this.periodEnd,
      dailyLimit: this.dailyLimit,
      dailyUsed: this.dailyUsed,
      weeklyLimit: this.weeklyLimit,
      weeklyUsed: this.weeklyUsed,
      monthlyLimit: this.monthlyLimit,
      monthlyUsed: this.monthlyUsed,
      errorCode: this.errorCode,
      errorMessage: this.errorMessage
    }
  }
}

/**
 * 从原始数组创建 TokenData 列表
 * @param {Array} rawData - 手机端返回的原始数据
 * @returns {TokenData[]}
 */
export function createTokenDataList(rawData) {
  if (!Array.isArray(rawData)) return []
  return rawData.map(item => new TokenData(item))
}
