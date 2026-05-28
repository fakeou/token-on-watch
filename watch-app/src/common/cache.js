/**
 * cache.js - 本地缓存模块
 *
 * 使用 @system.storage API 封装缓存操作
 * 支持 token 数据、时间戳的存取和过期判断
 */
import storage from '@system.storage'

const CACHE_PREFIX = 'token_monitor_'

/**
 * 缓存管理器
 */
const cache = {
  /**
   * 存储数据
   * @param {string} key - 缓存键名
   * @param {*} value - 要存储的值（自动 JSON 序列化）
   * @returns {Promise<void>}
   */
  set(key, value) {
    return new Promise((resolve, reject) => {
      const serialized = JSON.stringify({
        data: value,
        timestamp: Date.now()
      })
      storage.set({
        key: CACHE_PREFIX + key,
        value: serialized,
        success: resolve,
        fail: (data, code) => {
          console.error('Cache set failed:', code, data)
          reject(new Error('Cache set failed: ' + code))
        }
      })
    })
  },

  /**
   * 读取数据
   * @param {string} key - 缓存键名
   * @returns {Promise<{data: *, timestamp: number}>}
   */
  get(key) {
    return new Promise((resolve, reject) => {
      storage.get({
        key: CACHE_PREFIX + key,
        success: (data) => {
          try {
            const parsed = JSON.parse(data)
            resolve(parsed)
          } catch (e) {
            resolve({ data: null, timestamp: 0 })
          }
        },
        fail: (data, code) => {
          console.error('Cache get failed:', code, data)
          resolve({ data: null, timestamp: 0 })
        }
      })
    })
  },

  /**
   * 获取缓存数据（不含时间戳包装）
   * @param {string} key - 缓存键名
   * @returns {Promise<*>}
   */
  getData(key) {
    return this.get(key).then(result => result.data)
  },

  /**
   * 清除所有缓存
   * @returns {Promise<void>}
   */
  clear() {
    return new Promise((resolve, reject) => {
      // storage.clear 清除所有存储
      storage.clear({
        success: resolve,
        fail: (data, code) => {
          console.error('Cache clear failed:', code, data)
          reject(new Error('Cache clear failed: ' + code))
        }
      })
    })
  },

  /**
   * 判断缓存是否过期
   * @param {string} key - 缓存键名
   * @param {number} maxAge - 最大有效时长（毫秒），默认 5 分钟
   * @returns {Promise<boolean>} true 表示已过期
   */
  isStale(key, maxAge = 5 * 60 * 1000) {
    return this.get(key).then(result => {
      if (!result.timestamp) return true
      return (Date.now() - result.timestamp) > maxAge
    })
  },

  /**
   * 获取缓存时间戳
   * @param {string} key - 缓存键名
   * @returns {Promise<number>}
   */
  getTimestamp(key) {
    return this.get(key).then(result => result.timestamp || 0)
  }
}

export default cache
