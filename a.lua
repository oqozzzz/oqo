local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local io = require("io")
local redstone = component.proxy(component.list("redstone")())
local transposer = component.proxy(component.list("transposer")())
local sides = require("sides")

-- 定义反应堆（目标容器）中各槽位：
local coolantSlots = {3, 6, 9, 10, 15, 22, 26, 29, 33, 40, 45, 46, 49, 52}  -- 冷却剂目标槽位
local fuelSlots    = {1, 2, 4, 5, 7, 8, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 23, 24, 25, 27, 28, 30, 31, 32, 34, 35, 36, 37, 38, 39, 41, 42, 43, 44, 47, 48, 50, 51, 53, 54}  -- 燃料棒目标槽位
-- 定义各个接口面（根据实际安装情况修改）：
local redstoneInputSide_warning = sides.east  -- 红石输入面，用于温度监控器
local redstoneInputSide = sides.south  -- 红石输入面，用于检测电量
local redstoneInputSide_mode = sides.west  -- 红石输入面，用于切换程序模式
local redstoneOutputSide = sides.up   -- 红石输出面，用于关闭与激活反应堆
local meInterfaceSide = sides.up     -- ME接口面（提供燃料和冷却剂和输出取出物品）
local reactorChamberSide = sides.down   -- 反应堆（目标容器）面
-- ME接口中，物品所在的槽位：
local fuelRodSlot = 1  -- 燃料棒槽位
local coolantCellSlot = 2  -- 冷却剂槽位

-- 函数：程序睡眠
local function sleep(time)
  computer.pullSignal(time)
end

-- 函数：设置红石输出，用于激活或停用反应堆
local function redstoneOutput(side, level)
  redstone.setOutput(side, level)
end

-- 函数：检测红石输入（当输入大于8时认为激活）
local function redstoneInput(side)
  local inputLevel = redstone.getInput(side)
  return inputLevel > 8
end

-- 函数：转移物品
local function transferItems(from,to,item_slot,items_list)
  for _, targetSlot in ipairs(items_list) do
    local transferredCount = transposer.transferItem(from,to,1,item_slot,targetSlot)
    if transferredCount == 1 then
      
    else
      
      return false
    end
    sleep(0.5) -- 等待0.5秒
  end
  return true
end

-- 综合转移操作：依次转移反应堆异常列表标记缺失的冷却剂和燃料棒
local function performTransfers(warning_list)
  local coolantOK = transferItems(meInterfaceSide,reactorChamberSide,coolantCellSlot,warning_list.coolant)
  local fuelOK = transferItems(meInterfaceSide,reactorChamberSide,fuelRodSlot,warning_list.fuel)

  if coolantOK and fuelOK then
    return true
  else
    return false
  end
end

-- 函数：触发报警（实际报警功能待实现）
local function triggerAlarm()
  -- print("报警：物品转移失败！(报警功能待实现)") 
  -- 此处可添加发送警报信息、记录日志、闪烁指示灯等实际报警代码
end

-- 可选函数：检查反应堆状态（例如各槽位物品情况）
local function checkReactor()
  local fuelWarnings = false
  local coolantWarnings = false
  local Warnings = {fuel = {}, coolant = {}}
  -- 检查燃料棒槽位
  for _, slot in ipairs(fuelSlots) do
    local stack = transposer.getStackInSlot(reactorChamberSide, slot)
    if not stack or stack.name == "gregtech:gt.sunnariumCell" or string.find(stack.name, "Dep") or stack.maxDamage == 0 then
      table.insert(Warnings.fuel,slot)
      fuelWarnings = true
    end
  end
  -- 检查冷却剂槽位
  for _, slot in ipairs(coolantSlots) do
    local stack = transposer.getStackInSlot(reactorChamberSide, slot)
    if not stack or stack.damage > 80 then -- 冷却剂耗损超过80%时报警
      table.insert(Warnings.coolant,slot)
      coolantWarnings = true
    end
  end
  return not (fuelWarnings or coolantWarnings),Warnings
end

-- 函数：移除异常物品（枯竭燃料棒或者低耐久冷却剂）
local function removeItems(warnings)
  -- 如果警告表中有燃料棒需要取出，则逐一处理
  redstoneOutput(redstoneOutputSide, 0)  -- 停用反应堆
  sleep(2)  -- 等待2秒，确保反应堆停用
  if #warnings.fuel > 0 then
    for _, slot in ipairs(warnings.fuel) do
      local count = transposer.transferItem(reactorChamberSide,meInterfaceSide,1,slot,9)
      sleep(0.5)  -- 等待0.5秒
    end
  end
  -- 如果警告表中有冷却剂需要取出，则逐一处理
  if #warnings.coolant > 0 then
    for _, slot in ipairs(warnings.coolant) do
      local count = transposer.transferItem(reactorChamberSide,meInterfaceSide,1,slot,9)
      sleep(0.5)  -- 等待0.5秒
    end
  end
end

-- 函数：显示模式
local function displayMode()
  if redstoneInput(redstoneInputSide_warning) then
    print("温度监控器发出警告信号，不启用反应堆！")
    redstoneOutput(redstoneOutputSide, 0)  -- 停用反应堆
    elseif redstoneInput(redstoneInputSide) then
    print("开始检查反应堆槽位物品状态...")
    -- 首先检查反应堆槽位中的物品情况
    local chamberOK, warnings = checkReactor()

    if chamberOK then
      sleep(0.5)  -- 等待0.5秒
      redstoneOutput(redstoneOutputSide, 15)  -- 激活反应堆
    else
      removeItems(warnings)
      print("反应堆物品状态异常，存在以下问题：")
      if #warnings.fuel > 0 then
        print("缺少燃料棒的槽位：" .. table.concat(warnings.fuel, ", "))
      end
      if #warnings.coolant > 0 then
        print("缺少冷却剂或冷却剂损耗超过阈值的槽位：" .. table.concat(warnings.coolant, ", "))
      end
      print("开始执行物品转移操作...")
      local transfersOK = performTransfers(warnings)

      if transfersOK then
        chamberOK, warnings = checkReactor()
        if chamberOK then
          print("检查完毕，反应堆物品状态正常。激活反应堆...")
          sleep(0.5)  -- 等待0.5秒
          redstoneOutput(redstoneOutputSide, 15)  -- 激活反应堆
        else
          print("物品转移后反应堆状态仍异常，触发报警！")
          triggerAlarm()
        end
      else
        triggerAlarm()
      end
    end
  else
    print("未检测到红石输入信号，不启用反应堆！")
  end
end

-- 函数：静默模式
local function silentMode()
  if redstoneInput(redstoneInputSide_warning) then
    redstoneOutput(redstoneOutputSide, 0)  -- 停用反应堆
    elseif redstoneInput(redstoneInputSide) then
    -- 首先检查反应堆槽位中的物品情况
    local chamberOK, warnings = checkReactor()

    if chamberOK then
      sleep(0.5)  -- 等待0.5秒
      redstoneOutput(redstoneOutputSide, 15)  -- 激活反应堆
    else
      removeItems(warnings)
      local transfersOK = performTransfers(warnings)

      if transfersOK then
        chamberOK, warnings = checkReactor()
        if chamberOK then
          sleep(0.5)  -- 等待0.5秒
          redstoneOutput(redstoneOutputSide, 15)  -- 激活反应堆
        else
          triggerAlarm()
        end
      else
        triggerAlarm()
      end
    end
  else
  end
end

-- 函数：配置模式
local function configMode()
  print("配置模式尚未实现！")
end

-- 函数：初始化
local function initial()
  redstoneOutput(redstoneOutputSide, 0)  -- 停用反应堆
  print("输入0进入配置模式，输入1以显示反应堆状态的模式运行，输入2以静默运行,输入其他字符退出程序：")
  print("请在控制台输入对应指令：")
  local playerInput = io.read()
  return playerInput
end

-- 函数：主程序
local function main()
  print("程序启动！")
  if 1 == 2 then
    print("功能还没实现！")
  else
    local playerInput = initial()
    while true do
      if playerInput == "0" then
        configMode()
      elseif playerInput == "1" then
        displayMode()
      elseif playerInput == "2" then
        silentMode()
      else
        print("程序退出！")
        return
      end
      if not redstoneInput(redstoneInputSide_mode) then
        playerInput = initial()
      end
      -- 根据需要设置检测周期
      computer.pullSignal(1)  -- 每1秒检查一次
    end
  end
end

-- 启动程序
main()

-- 启动程序
main()
