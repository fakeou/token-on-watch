/**
 * connector.js - Interconnect 通信模块
 *
 * Vela 快应用侧使用 @system.interconnect.instance() 与手机端
 * Xiaomi XMS Wearable MessageApi 通信。业务消息仍然沿用 protocol.md：
 * query/response/refresh_one/push/error/ping/pong。
 */
import interconnect from '@system.interconnect'

const Protocol = {
  ACTION_QUERY: 'query',
  ACTION_RESPONSE: 'response',
  ACTION_REFRESH_ONE: 'refresh_one',
  ACTION_PUSH: 'push',
  ACTION_ERROR: 'error',
  ACTION_PING: 'ping',
  ACTION_PONG: 'pong'
}

function generateRequestId() {
  return 'req_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9)
}

function parseIncoming(data) {
  const raw = data && data.data !== undefined ? data.data : data
  if (typeof raw === 'string') {
    return JSON.parse(raw)
  }
  if (raw && typeof raw === 'object' && typeof raw.message === 'string') {
    return JSON.parse(raw.message)
  }
  if (raw && typeof raw === 'object' && raw.message && typeof raw.message === 'object') {
    return raw.message
  }
  return raw || {}
}

const connector = {
  _connected: false,
  _initialized: false,
  _conn: null,
  _messageHandler: null,
  _connectionHandler: null,
  _errorHandler: null,
  _pendingRequests: {},
  _requestTimeout: 10000,

  connect() {
    if (this._initialized) return
    this._initialized = true

    try {
      this._conn = interconnect.instance()

      this._conn.onopen = () => {
        console.log('[Connector] connection opened')
        this._connected = true
        if (this._connectionHandler) {
          this._connectionHandler(true)
        }
        this._sendHello()
      }

      this._conn.onclose = (data) => {
        console.log('[Connector] connection closed:', data && data.code, data && data.data)
        this._connected = false
        this._initialized = false
        this._clearPendingRequests('Connection closed')
        if (this._connectionHandler) {
          this._connectionHandler(false)
        }
      }

      this._conn.onerror = (data) => {
        console.error('[Connector] connection error:', data && data.code, data && data.data)
        this._connected = false
        if (this._errorHandler) {
          this._errorHandler(data)
        }
        if (this._connectionHandler) {
          this._connectionHandler(false)
        }
      }

      this._conn.onmessage = (data) => {
        this._handleIncoming(data)
      }
    } catch (e) {
      console.error('[Connector] Connect error:', e)
      this._connected = false
      this._initialized = false
      if (this._errorHandler) {
        this._errorHandler(e)
      }
    }
  },

  disconnect() {
    this._connected = false
    this._initialized = false
    this._clearPendingRequests('Disconnected')
    this._conn = null
  },

  query(sources = []) {
    return this._request({
      action: Protocol.ACTION_QUERY,
      sources: sources,
      timestamp: Date.now()
    })
  },

  refreshOne(sourceId) {
    return this._request({
      action: Protocol.ACTION_REFRESH_ONE,
      sourceId: sourceId,
      timestamp: Date.now()
    })
  },

  ping() {
    if (!this._connected) {
      return Promise.resolve(false)
    }

    return this._request({
      action: Protocol.ACTION_PING,
      timestamp: Date.now()
    }, 3000).then(() => true).catch(() => false)
  },

  onMessage(handler) {
    this._messageHandler = handler
  },

  onConnectionChange(handler) {
    this._connectionHandler = handler
  },

  onError(handler) {
    this._errorHandler = handler
  },

  checkConnection() {
    return this._connected
  },

  sendMessage(data) {
    return this._sendMessage(data)
  },

  requestData(sources = []) {
    return this.query(sources)
  },

  _request(message, timeoutMs) {
    return new Promise((resolve, reject) => {
      if (!this._connected) {
        reject(new Error('Not connected to phone'))
        return
      }

      const requestId = generateRequestId()
      const payload = Object.assign({}, message, { requestId: requestId })
      const timeout = setTimeout(() => {
        delete this._pendingRequests[requestId]
        reject(new Error('Request timeout'))
      }, timeoutMs || this._requestTimeout)

      this._pendingRequests[requestId] = { resolve, reject, timeout }

      this._sendMessage(payload).catch(e => {
        clearTimeout(timeout)
        delete this._pendingRequests[requestId]
        reject(e)
      })
    })
  },

  _sendHello() {
    const message = {
      action: Protocol.ACTION_PING,
      requestId: generateRequestId(),
      timestamp: Date.now()
    }

    this._sendMessage(message).catch(e => {
      console.error('[Connector] Hello failed:', e)
    })
  },

  _sendMessage(message) {
    return new Promise((resolve, reject) => {
      if (!this._conn || !this._conn.send) {
        reject(new Error('Interconnect instance is not ready'))
        return
      }

      try {
        this._conn.send({
          data: message,
          success: () => {
            console.log('[Connector] Sent:', message.action)
            resolve()
          },
          fail: (data) => {
            const code = data && data.code !== undefined ? data.code : 'unknown'
            const detail = data && data.data !== undefined ? data.data : ''
            console.error('[Connector] Send failed:', code, detail)
            reject(new Error('Send failed: ' + code))
          }
        })
      } catch (e) {
        console.error('[Connector] Send error:', e)
        reject(e)
      }
    })
  },

  _handleIncoming(data) {
    try {
      const message = parseIncoming(data)
      console.log('[Connector] Received:', message.action)

      if (message.action === Protocol.ACTION_RESPONSE ||
          message.action === Protocol.ACTION_ERROR ||
          message.action === Protocol.ACTION_PONG) {
        const pending = this._pendingRequests[message.requestId]
        if (pending) {
          clearTimeout(pending.timeout)
          delete this._pendingRequests[message.requestId]

          if (message.action === Protocol.ACTION_ERROR) {
            pending.reject(new Error(message.error || 'Unknown error'))
          } else {
            pending.resolve(message)
          }
        }
      }

      if (this._messageHandler) {
        this._messageHandler(message)
      }
    } catch (e) {
      console.error('[Connector] Parse message error:', e)
      if (this._errorHandler) {
        this._errorHandler(e)
      }
    }
  },

  _clearPendingRequests(reason) {
    Object.keys(this._pendingRequests).forEach(requestId => {
      const pending = this._pendingRequests[requestId]
      clearTimeout(pending.timeout)
      pending.reject(new Error(reason))
    })
    this._pendingRequests = {}
  }
}

export default connector
