## Feishu 应用配置（OpenClaw 机器人）速记

### 1) 一键导入权限（Scopes JSON）
在飞书开放平台 → 应用 → 权限管理（或“添加权限/批量导入”）里粘贴：
{
  "scopes": {
    "tenant": [
      "contact:contact.base:readonly",
      "aily:file:read",
      "aily:file:write",
      "application:application.app_message_stats.overview:readonly",
      "application:application:self_manage",
      "application:bot.menu:write",
      "cardkit:card:write",
      "contact:user.employee_id:readonly",
      "corehr:file:download",
      "docs:document.content:read",
      "event:ip_list",
      "im:chat",
      "im:chat.access_event.bot_p2p_chat:read",
      "im:chat.members:bot_access",
      "im:message",
      "im:message.group_at_msg:readonly",
      "im:message.group_msg",
      "im:message.p2p_msg:readonly",
      "im:message:readonly",
      "im:message:send_as_bot",
      "im:resource",
      "sheets:spreadsheet",
      "wiki:wiki:readonly"
    ],
    "user": [
      "aily:file:read",
      "aily:file:write",
      "im:chat.access_event.bot_p2p_chat:read"
    ]
  }
}

> 备注：tenant 是租户级权限，user 是用户授权相关（你这里主要是 aily/file + p2p chat access event）。

### 2) 一键开放事件（Event）
在飞书开放平台 → 事件订阅里，开启（订阅）：
`im.message.receive_v1`
> 这条是机器人收消息的关键事件。