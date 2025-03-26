local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local os = require("os")
local io = require("io")
local redstone = component.proxy(component.list("redstone")())
local transposer = component.proxy(component.list("transposer")())
local sides = require("sides")

-- 配置抽象化（集中管理参数）
local config = {
  reactor = {
    Side = sides.down,          -- 反应堆容器面
    fuelSlots = {1,2,4,5,7,8,11,12,13,14,16,17,18,19,20,21,23,24,25,27,28,30,31,32,34,35,36,37,38,39,41,42,43,44,47,48,50,51,53,54},
    coolantSlots = {3,6,9,10,15,22,26,29,33,40,45,46,49,52} -- 冷却单元反应堆槽位
  },
  meInterface = {
    side = sides.up,                   -- ME接口面
    fuelSlot = 1,                      -- 燃料棒源槽位
    coolantSlot = 2,                   -- 冷却单元源槽位 
    outputSlot = 9                     -- 物品回收槽位
  },
  redstone = {
    energyInput = sides.south,         -- 能量存储信号输入面
    temperatureInput = sides.east,     -- 温度监控信号输入面
    modeInput = sides.west,            -- 模式切换信号输入面
    reactorControl = sides.up,         -- 反应堆控制输出面
    activationThreshold = 8            -- 红石激活阈值
  },
  timing = {
    transferInterval = 0.2,            -- 物品转移间隔（秒）
    transferRetryInterval = 0.2,       -- 物品转移重试间隔（秒）
    maxTransferRetries = 2,            -- 最大转移重试次数
    safetyDelay = 1.6,                 -- 安全操作延迟（秒）
    mainDelay = 0.8,                   -- 主循环间隔（秒）
    normalDelay = 0.2                  -- 一般保留延迟（秒）
  }
}

local reactor = {
  isActive = false
}


-- 红石控制封装
function reactor:setState(active)
  redstone.setOutput(config.redstone.reactorControl, active and 15 or 0)
  self.isActive = active
end

-- 函数：触发报警（实际报警功能待实现）
local function triggerAlarm(reason)
  reactor:setState(false)
  print("[紧急关闭] 原因: " .. reason)
  -- 此处可添加发送警报信息、记录日志、闪烁指示灯等实际报警代码
end

-- 函数：检查模式切换
local function checkMode()
  return redstone.getInput(config.redstone.modeInput) > config.redstone.activationThreshold
end

-- 函数：检查能量存储
local function checkEnergy()
  return redstone.getInput(config.redstone.energyInput) > config.redstone.activationThreshold
end

-- 函数：检查温度监控
local function checkTemperature()
  return redstone.getInput(config.redstone.temperatureInput) > config.redstone.activationThreshold
end

-- 函数：反应堆燃料棒检查
local function getFuelStatus(side, slot)
  local stack = transposer.getStackInSlot(side, slot)
  if not stack or stack.name == "gregtech:gt.sunnariumCell" or string.find(stack.name, "Dep") or stack.maxDamage == 0 then
    return true -- 燃料棒缺失或已枯竭
  end
end

-- 函数：反应堆冷却单元检查
local function getCoolantStatus(side, slot)
  local stack = transposer.getStackInSlot(side, slot)
  if not stack or stack.damage > 80 then
    return true -- 冷却单元缺失或耗损过多
  end
end

-- 函数：反应堆整体检查
local function checkReactor()
  local status = {
    energyOK = checkEnergy(),
    temperatureOK = not checkTemperature(),  -- 温度信号高表示异常
    fuel = {},
    coolant = {}
  }

  for _, slot in ipairs(config.reactor.fuelSlots) do
    if getFuelStatus(config.reactor.Side, slot) then
      table.insert(status.fuel, slot)
    end
  end

  for _, slot in ipairs(config.reactor.coolantSlots) do
    if getCoolantStatus(config.reactor.Side, slot) then
      table.insert(status.coolant, slot)
    end
  end

  return status
end

-- 函数：物品转移
local function transferItems(fromSide, toSide, fromSlot, toSlot, maxRetries)
  local retries = 0
  while retries <= (maxRetries or config.timing.maxTransferRetries) do
    local transferred = transposer.transferItem(fromSide, toSide,1, fromSlot, toSlot)
    if transferred == 1 then
      return true
    end
    retries = retries + 1
    os.sleep(config.timing.transferRetryInterval) -- 重试等待（秒）
  end
  return false
end

-- 函数：反应堆整体物品转移处理
local function ItemHandling(status)
  -- 阶段1: 移除异常物品
  for _, slot in ipairs(status.fuel) do
    transferItems(config.reactor.Side, config.meInterface.side, slot, config.meInterface.outputSlot, config.timing.maxTransferRetries)
  end
  for _, slot in ipairs(status.coolant) do
    transferItems(config.reactor.Side, config.meInterface.side, slot, config.meInterface.outputSlot, config.timing.maxTransferRetries)
  end

  -- 阶段2: 补充物资
  local function replenish(items, sourceSlot)
    for _, slot in ipairs(items) do
      if not transferItems(config.meInterface.side, config.reactor.Side, sourceSlot, slot, config.timing.maxTransferRetries) then
        return false
      end
    end
    return true
  end

  return replenish(status.fuel, config.meInterface.fuelSlot) and replenish(status.coolant, config.meInterface.coolantSlot)
end

-- 函数：显示模式
local function displayMode()
  print("开始检查反应堆状态...")
  local status = checkReactor()

  if not status.energyOK then
    reactor:setState(false)
    os.sleep(5)  -- 增加检测间隔
    goto continue
  end

  if not status.temperatureOK then
    triggerAlarm("温度异常")
  elseif #status.fuel > 0 or #status.coolant > 0 then
    reactor:setState(false)
    print("反应堆有物品缺失或需要更换，已暂停运行...")
    if #status.fuel > 0 then
      print("缺少燃料棒的槽位：" .. table.concat(status.fuel, ", "))
    end
    if #status.coolant > 0 then
      print("缺少冷却单元或冷却单元损耗超过阈值的槽位：" .. table.concat(status.coolant, ", "))
    end
    os.sleep(config.timing.safetyDelay)  -- 安全操作延迟（秒）
    print("开始处理异常物品...")
    if ItemHandling(status) then
      os.sleep(config.timing.normalDelay)
      print("反应堆一切正常，激活反应堆...")
      reactor:setState(true)
    end
  else
    os.sleep(config.timing.normalDelay)
    reactor:setState(true)
  end

  ::continue::
  os.sleep(config.timing.mainDelay)  -- 主循环间隔（秒）
end

-- 函数：静默模式
local function silentMode()
  local status = checkReactor()

  if not status.energyOK then
    reactor:setState(false)
    os.sleep(5)  -- 增加检测间隔
    goto continue
  end

  if not status.temperatureOK then
    triggerAlarm("温度异常")
  elseif #status.fuel > 0 or #status.coolant > 0 then
    reactor:setState(false)
    os.sleep(config.timing.safetyDelay)  -- 安全操作延迟（秒）
    if ItemHandling(status) then
      os.sleep(config.timing.normalDelay)
      reactor:setState(true)
    end
  else
    os.sleep(config.timing.normalDelay)
    reactor:setState(true)
  end

  ::continue::
  os.sleep(config.timing.mainDelay) -- 主循环间隔（秒）
end

-- 函数：配置模式
local function configMode()
  print("配置模式尚未实现！")
end

-- 函数：初始化
local function initial()
  reactor:setState(false)
  print("输入0进入配置模式，输入1以显示反应堆状态的模式运行，输入2以静默运行,输入其他字符退出程序。")
  print("请在控制台输入对应指令：")
  local playerInput = io.read()
  return playerInput
end

-- 函数：主程序
local function main()
  print("程序启动！")
  while true do
    local playerInput = initial()
    if playerInput == "0" then
      configMode()
    elseif playerInput == "1" then
      while checkMode() do
        displayMode()
        os.sleep(config.timing.normalDelay)
      end
    elseif playerInput == "2" then
      while checkMode() do
        silentMode()
        os.sleep(config.timing.normalDelay)
      end
    else
      print("程序退出！")
      return
    end
  end
end

-- 启动程序
main()
