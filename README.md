# Grow a Garden 2 Autofarm Hub

## Permanent Loadstring

Use this same loadstring every time. When `main.lua` is updated on GitHub, this URL keeps pointing at the newest version on the `master` branch.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/jimmynewtronamongus/autofarm-service/master/main.lua"))()
```

Do not copy a commit-specific raw URL from GitHub. Those URLs include a version hash and will change every update.

## Files

`main.lua` is the current client GUI script used by the permanent loadstring above.

`Main.server.lua` is the executor/local GUI loader. It only runs on the client.

For buttons to affect gameplay in your own game, add `ServerBridge.server.lua` to `ServerScriptService` and put your Roblox user id in `OWNER_USER_IDS`.

## Server Action Bindables

`ServerBridge.server.lua` creates this folder:

`ServerScriptService.DevScriptHubActions`

Wire these `BindableFunction` objects to your own game systems:

- `CollectFruit(player, radius)` -> return collected count or `true`
- `PlaceSeed(player, seedName)` -> return `true` when a seed is placed
- `SellInventory(player)` -> return `true` when sold
- `BuySeed(player, seedName, amount)` -> return `true` when bought

The executor GUI sends only high-level requests. The server bridge performs permission checks and owns the real gameplay actions.

## Clean Remote API

The GUI calls:

- `Action:FireServer("collectFruit", { radius = 250 })`
- `Action:FireServer("placeSeed", { seedName = "Carrot" })`
- `Action:FireServer("sellInventory")`
- `Action:FireServer("buySeed", { seedName = "Carrot", amount = 1 })`
- `Action:FireServer("setMode", { mode = "autoHarvest", enabled = true })`
- `Action:FireServer("setEnabled", { enabled = true })`