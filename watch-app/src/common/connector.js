/**
 * connector.js - Interconnect 通信模块
 *
 * 使用 @system.interconnect API 与手机端 Flutter App 通信
 * 按照 protocol.md 规范实现消息收发
 *
 * 消息类型：
 * - query: 手表请求查询 token 数据
 * - response: 手机返回查询结果
 * - refresh_one: 手表请求刷新单个源
 * - push: 手机主动推送数据
 * - error: 错误响应
 * - ping/pong: 连接状态检查
 */
import interconnect from '@system.interconnect'

/**
 * 通信协议常量
 */
const Protocol = {
  ACTION_QUERY: 'query',
  ACTION_RESPONSE: 'response',
  ACTION_REFRESH_ONE: 'refresh_one',
  ACTION_PUSH: 'push',
  ACTION_ERROR: 'error',
  ACTION_PING: 'ping',
  ACTION_PONG: 'pong'
}

/**
 * 生成简单的 UUID
 * @returns {string}
 */
function generateRequestId() {
  return 'req_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9)
}

/**
 * 通信管理器单例
 */
const connector = {
  /** @type {boolean} 连接状态 */
  _connected: false,

  /** @type {boolean} 是否已初始化 */
  _initialized: false,

  /** @type {Function|null} 消息回调 */
  _messageHandler: null,

  /** @type {Function|null} 连接状态变化回调 */
  _connectionHandler: null,

  /** @type {Function|null} 错误回调 */
  _errorHandler: null,

  /** @type {Object} 待处理的请求 Map<requestId, {resolve, reject, timeout}> */
  _pendingRequests: {},

  /** @type {number} 请求超时时间 (ms) */
  _requestTimeout: 10000,

  /**
   * 初始化连接
   * 建立与手机端的 interconnect 通信
   */
  connect() {
    if (this._initialized) return

    this._initialized = true

    try {
      interconnect.connect({
        success: () => {
          console.log('[Connector] Connected to phone app')
          this._connected = true
          if (this._connectionHandler) {
            this._connectionHandler(true)
          }
        },
        fail: (data, code) => {
          console.error('[Connector] Connection failed:', code, data)
          this._connected = false
          if (this._connectionHandler) {
            this._connectionHandler(false)
          }
        }
      })

      // 监听连接断开事件
      interconnect.onDisconnect(() => {
        console.log('[Connector] Disconnected from phone app')
        this._connected = false
        this._initialized = false

        // 清理所有待处理请求
        this._clearPendingRequests('Connection lost')

        if (this._connectionHandler) {
          this._connectionHandler(false)
        }
      })
    } catch (e) {
      console.error('[Connector] Connect error:', e)
      this._connected = false
    }
  },

  /**
   * 断开连接
   */
  disconnect() {
    try {
      interconnect.disconnect()
    } catch (e) {
      console.error('[Connector] Disconnect error:', e)
    }
    this._connected = false
    this._initialized = false
    this._clearPendingRequests('Disconnected')
  },

  /**
   * 查询 token 数据
   * @param {string[]} sources - API 源 ID 列表，空数组表示查询所有
   * @returns {Promise<Object>} 返回 token 数据
   */
  query(sources = []) {
    return new Promise((resolve, reject) => {
      if (!this._connected) {
        reject(new Error('Not connected to phone'))
        return
      }

      const requestId = generateRequestId()
      const message = {
        action: Protocol.ACTION_QUERY,
        requestId: requestId,
        sources: sources,
        timestamp: Date.now()
      }

      // 设置超时
      const timeout = setTimeout(() => {
        delete this._pendingRequests[requestId]
        reject(new Error('Request timeout'))
      }, this._requestTimeout)

      // 保存待处理请求
      this._pendingRequests[requestId] = { resolve, reject, timeout }

      // 发送消息
      this._sendMessage(message).catch(e => {
        clearTimeout(timeout)
        delete this._pendingRequests[requestId]
        reject(e)
      })
    })
  },

  /**
   * 请求刷新单个源
   * @param {string} sourceId - 源 ID
   * @returns {Promise<Object>}
   */
  refreshOne(sourceId) {
    return new Promise((resolve, reject) => {
      if (!this._connected) {
        reject(new Error('Not connected to phone'))
        return
      }

      const requestId = generateRequestId()
      const message = {
        action: Protocol.ACTION_REFRESH_ONE,
        requestId: requestId,
        sourceId: sourceId,
        timestamp: Date.now()
      }

      const timeout = setTimeout(() => {
        delete this._pendingRequests[requestId]
        reject(new Error('Request timeout'))
      }, this._requestTimeout)

      this._pendingRequests[requestId] = { resolve, reject, timeout }

      this._sendMessage(message).catch(e => {
        clearTimeout(timeout)
        delete this._pendingRequests[requestId]
        reject(e)
      })
    })
  },

  /**
   * 发送 Ping 检查连接
   * @returns {Promise<boolean>}
   */
  ping() {
    return new Promise((resolve, reject) => {
      if (!this._connected) {
        resolve(false)
        return
      }

      const requestId = generateRequestId()
      const message = {
        action: Protocol.ACTION_PING,
        requestId: requestId,
        timestamp: Date.now()
      }

      const timeout = setTimeout(() => {
        delete this._pendingRequests[requestId]
        resolve(false)
      }, 3000) // Ping 超时时间较短

      this._pendingRequests[requestId] = {
        resolve: () => resolve(true),
        reject: () => resolve(false),
        timeout
      }

      this._sendMessage(message).catch(() => {
        clearTimeout(timeout)
        delete this._pendingRequests[requestId]
        resolve(false)
      })
    })
  },

  /**
   * 注册消息接收回调
   * @param {Function} handler - 消息处理函数
   */
  onMessage(handler) {
    this._messageHandler = handler

    try {
      interconnect.onMessage((message) => {
        try {
          const data = typeof message === 'string' ? JSON.parse(message) : message
          console.log('[Connector] Received:', data.action)

          // 处理响应类消息（匹配 requestId）
          if (data.action === Protocol.ACTION_RESPONSE ||
              data.action === Protocol.ACTION_ERROR ||
              data.action === Protocol.ACTION_PONG) {

            const pending = this._pendingRequests[data.requestId]
            if (pending) {
              clearTimeout(pending.timeout)
              delete this._pendingRequests[data.requestId]

              if (data.action === Protocol.ACTION_ERROR) {
                pending.reject(new Error(data.error || 'Unknown error'))
              } else {
                pending.resolve(data)
              }
            }
          }

          // 调用通用消息回调
          if (this._messageHandler) {
            this._messageHandler(data)
          }
        } catch (e) {
          console.error('[Connector] Parse message error:', e)
        }
      })
    } catch (e) {
      console.error('[Connector] onMessage error:', e)
    }
  },

  /**
   * 注册连接状态变化回调
   * @param {Function} handler - 状态处理函数，参数为 boolean
   */
  onConnectionChange(handler) {
    this._connectionHandler = handler
  },

  /**
   * 注册错误回调
   * @param {Function} handler - 错误处理函数
   */
  onError(handler) {
    this._errorHandler = handler
  },

  /**
   * 检查当前连接状态
   * @returns {boolean}
   */
  checkConnection() {
    return this._connected
  },

  /**
   * 发送消息到手机端
   * @param {Object} message - 消息对象
   * @returns {Promise<void>}
   * @private
   */
  _sendMessage(message) {
    return new Promise((resolve, reject) => {
      try {
        interconnect.postMessage({
          message: JSON.stringify(message),
          success: () => {
            console.log('[Connector] Sent:', message.action)
            resolve()
          },
          fail: (data, code) => {
            console.error('[Connector] Send failed:', code, data)
            reject(new Error('Send failed: ' + code))
          }
        })
      } catch (e) {
        console.error('[Connector] PostMessage error:', e)
        reject(e)
      }
    })
  },

  /**
   * 清理所有待处理请求
   * @param {string} reason - 清理原因
   * @private
   */
  _clearPendingRequests(reason) {
    Object.keys(this._pendingRequests).forEach(requestId => {
      const pending = this._pendingRequests[requestId]
      clearTimeout(pending.timeout)
      pending.reject(new Error(reason))
    })
    this._pendingRequests = {}
  },

  /**
   * 发送自定义消息（兼容旧接口）
   * @param {Object} data - 要发送的数据对象
   * @returns {Promise<void>}
   */
  sendMessage(data) {
    return this._sendMessage(data)
  },

  /**
   * 请求数据（兼容旧接口）
   * @param {string[]} sources
   * @returns {Promise<Object>}
   */
  requestData(sources = []) {
    return this.query(sources)
  }
}

export default connector
