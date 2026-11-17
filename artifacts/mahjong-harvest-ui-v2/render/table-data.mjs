// Same shanten and ukeire share a priority. The smallest priority is best.
export const hand = [
  { suit: 'Wan', rank: 1, shanten: 1, ukeire: 18, priority: 3 },
  { suit: 'Wan', rank: 2, shanten: 1, ukeire: 11, priority: 7 },
  { suit: 'Wan', rank: 3, shanten: 1, ukeire: 11, priority: 7 },
  { suit: 'Wan', rank: 4, shanten: 1, ukeire: 15, priority: 4 },
  { suit: 'Wan', rank: 5, shanten: 1, ukeire: 11, priority: 7 },
  { suit: 'Wan', rank: 6, shanten: 1, ukeire: 14, priority: 5 },
  { suit: 'Wan', rank: 9, shanten: 0, ukeire: 8, priority: 1 },
  { suit: 'Tong', rank: 7, shanten: 1, ukeire: 11, priority: 7 },
  { suit: 'Tong', rank: 8, shanten: 1, ukeire: 11, priority: 7 },
  { suit: 'Tong', rank: 9, shanten: 1, ukeire: 15, priority: 4 },
  { suit: 'Tiao', rank: 2, shanten: 1, ukeire: 13, priority: 6 },
  { suit: 'Tiao', rank: 2, shanten: 1, ukeire: 13, priority: 6 },
  { suit: 'Tiao', rank: 5, shanten: 1, ukeire: 31, priority: 2 },
  { suit: 'Tiao', rank: 6, shanten: 1, ukeire: 31, priority: 2 },
];

export const players = [
  { name: '小满', wind: '东', score: 0, avatar: 0 },
  { name: '青禾', wind: '南', score: 0, avatar: 1 },
  { name: '阿泽', wind: '西', score: 0, avatar: 2 },
  { name: '云生', wind: '北', score: 0, avatar: 3 },
];

// Public tiles for the ordinary table example, in seat order.
export const discards = [
  [{ suit: 'Tong', rank: 2 }, { suit: 'Tiao', rank: 9 }, { suit: 'Tong', rank: 4 }],
  [{ suit: 'Tong', rank: 1 }, { suit: 'Tong', rank: 5 }, { suit: 'Tiao', rank: 1 }],
  [{ suit: 'Tong', rank: 3 }, { suit: 'Tong', rank: 2 }, { suit: 'Tiao', rank: 9 }],
  [{ suit: 'Tiao', rank: 1 }, { suit: 'Tong', rank: 3 }, { suit: 'Tong', rank: 5 }],
];

// Unseen copies after a hypothetical discard of the nine characters.
export const waits = [
  { suit: 'Tiao', rank: 4, count: 4 },
  { suit: 'Tiao', rank: 7, count: 4 },
];

export const tableScreens = [
  { id: '14', slug: 'bot-training', title: '人机训练牌桌', mode: 'bot', state: 'idle', overlay: 'none' },
  { id: '15', slug: 'tile-practice', title: '摸打练习', mode: 'practice', state: 'idle', overlay: 'none' },
  { id: '16', slug: 'table', title: '横屏 3D 牌桌', mode: 'friend', state: 'idle', overlay: 'none' },
  { id: '17', slug: 'discard-efficiency', title: '普通选牌与打出', mode: 'friend', state: 'selected', overlay: 'none' },
  { id: '18', slug: 'claim-response', title: '出牌响应', mode: 'friend', state: 'reaction', overlay: 'none' },
  { id: '19', slug: 'kong-choice', title: '选择杠牌', mode: 'friend', state: 'reaction', overlay: 'kong' },
  { id: '20', slug: 'table-rules', title: '本桌规则', mode: 'friend', state: 'idle', overlay: 'rules' },
  { id: '21', slug: 'settings-basic', title: '基础设置', mode: 'friend', state: 'idle', overlay: 'settings-basic' },
  { id: '22', slug: 'settings-audio', title: '音效设置', mode: 'friend', state: 'idle', overlay: 'settings-audio' },
  { id: '23', slug: 'settings-graphics', title: '画面设置', mode: 'friend', state: 'idle', overlay: 'settings-graphics' },
  { id: '24', slug: 'settings-rules', title: '玩法规则', mode: 'friend', state: 'idle', overlay: 'settings-rules' },
  { id: '25', slug: 'quick-chat', title: '快捷聊天', mode: 'friend', state: 'idle', overlay: 'chat' },
  { id: '26', slug: 'emotes', title: '牌桌表情', mode: 'friend', state: 'idle', overlay: 'emotes' },
  { id: '27', slug: 'hold-to-talk', title: '按住说话', mode: 'friend', state: 'voice', overlay: 'none' },
  { id: '28', slug: 'player-management', title: '牌友管理', mode: 'friend', state: 'idle', overlay: 'manage' },
  { id: '29', slug: 'leave-table', title: '离开牌桌确认', mode: 'friend', state: 'idle', overlay: 'leave' },
  { id: '31', slug: 'settlement', title: '本局结算', mode: 'friend', state: 'idle', overlay: 'settlement' },
  { id: '38', slug: 'effective-tile-count', title: '进牌张数标签', mode: 'friend', state: 'badges', overlay: 'none' },
  { id: '39', slug: 'effective-tile-panel', title: '进牌详情面板', mode: 'friend', state: 'details', overlay: 'none' },
];
