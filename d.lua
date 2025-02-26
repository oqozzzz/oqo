local component = require("component")
local computer = require("computer")
local rs = component.redstone
local tr = component.transposer
local sides = require("sides")

-- 定义反应堆（目标容器）中各槽位：
local coolantSlots = {3, 6, 9, 10, 15, 22, 26, 29, 33, 40, 45, 46, 49, 52}  -- 冷却剂目标槽位
local fuelSlots    = {1, 2, 4, 5, 7, 8, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 23, 24, 25, 27, 28, 30, 31, 32, 34, 35, 36, 37, 38, 39, 41, 42, 43, 44, 47, 48, 50, 51, 53, 54}  -- 燃料棒目标槽位
-- 定义各个接口面（根据实际安装情况修改）：
local redstoneInputSide = sides.south  -- 红石输入面，用于检测电量
local reactorActivationSide = sides.down   -- 红石输出面，用于激活反应堆
local meInterfaceSide = sides.up     -- ME接口面（提供燃料和冷却剂和输出取出物品）
local reactorChamberSide = sides.down   -- 反应堆（目标容器）面
-- ME接口中，物品所在的槽位：
local fuelRodSlot     = 1  -- 燃料棒槽位
local coolantCellSlot = 2  -- 冷却剂槽位

-- 函数：程序睡眠
local function sleep(time)
  computer.pullSignal(time)
end

-- 函数：转移物品
local function transferitems(from,to,item_slot,items_list)
  
  for _, targetSlot in ipairs(items_list) do
    local transferredCount = tr.transferItem(from,to,1,item_slot,targetSlot)
    if transferredCount == 1 then
      print("物品成功转移到反应堆槽位 " .. targetSlot)
    else
      print("错误：无法将物品转移到反应堆槽位 " .. targetSlot)
      return false
    end
    sleep(0.5) -- 等待0.5秒
  end
  return true
end

-- 函数：检测红石输入（当输入大于8时认为激活）
local function isRedstoneInputActive()
  local inputLevel = rs.getInput(redstoneInputSide)
  return inputLevel > 8
end

-- 函数：激活反应堆（通过输出红石信号）
local function activateReactor()
  rs.setOutput(reactorActivationSide, 15)
  print("反应堆已激活！")
end

-- 函数：停用反应堆（通过关闭红石信号）
local function deactivateReactor()
  rs.setOutput(reactorActivationSide, 0)
  print("反应堆已停用。")
end

-- 综合转移操作：依次转移冷却剂和燃料棒
local function performTransfers(warning_list)
  deactivateReactor()
  print("开始执行物品转移操作...")
  local coolantOK = transferitems(meInterfaceSide,reactorChamberSide,coolantCellSlot,warning_list.coolant)
  local fuelOK = transferitems(meInterfaceSide,reactorChamberSide,fuelRodSlot,warning_list.fuel)

  if coolantOK and fuelOK then
    print("所有物品转移成功！")
    return true
  else
    print("物品转移过程中出现错误！")
    return false
  end
end

-- 函数：触发报警（实际报警功能待实现）
local function triggerAlarm()
  print("报警：物品转移失败！(报警功能待实现)")
  -- 此处可添加发送警报信息、记录日志、闪烁指示灯等实际报警代码
end

-- 可选函数：检查反应堆状态（例如各槽位物品情况）
local function checkReactorChamber()
  local fuelWarnings = false
  local coolantWarnings = false
  local Warnings = {fuel = {},coolant = {}}

  -- 检查燃料棒槽位
  for _, slot in ipairs(fuelSlots) do
    local stack = tr.getStackInSlot(reactorChamberSide, slot)
    if not stack or stack.name == "gregtech:gt.sunnariumCell" or string.find(stack.name, "Dep") or stack.maxDamage == 0 then
      table.insert(Warnings.fuel,slot)
      fuelWarnings = true
    end
  end

  -- 检查冷却剂槽位
  for _, slot in ipairs(coolantSlots) do
    local stack = tr.getStackInSlot(reactorChamberSide, slot)
    if not stack or stack.damage > 80 then -- 冷却剂耗损超过80%时报警
      table.insert(Warnings.coolant,slot)
      coolantWarnings = true
    end
  end

  if fuelWarnings then
    print("燃料棒存在问题，请检查！")
    print("警告：反应堆槽位 " .. table.concat(Warnings.fuel, ", ") .. " 缺少燃料棒或者已枯竭！")
  else
    print("燃料棒状态正常。")
  end

  if coolantWarnings then
    print("冷却剂存在问题，请检查！")
    print("警告：反应堆槽位 " .. table.concat(Warnings.coolant, ",") .. " 缺少冷却剂！")
  else
    print("冷却剂状态正常。")
  end
  return not (fuelWarnings or coolantWarnings),Warnings
end

local function removeExhaustedItems(warnings)
  -- 如果警告表中有燃料棒需要取出，则逐一处理
  deactivateReactor()
  sleep(2)  -- 等待2秒，确保反应堆停用
  print("开始取出枯竭物品或者低耐久冷却剂...")
  if #warnings.fuel > 0 then
    for _, slot in ipairs(warnings.fuel) do
      local count = tr.transferItem(reactorChamberSide,meInterfaceSide,1,slot,9)
      if count and count > 0 then
        print("成功取出燃料棒槽位 " .. slot)
      else
        print("取出燃料棒槽位 " .. slot .. " 失败！")
      end
      sleep(0.5)  -- 等待0.5秒
    end
  end
  
  -- 如果警告表中有冷却剂需要取出，则逐一处理
  if #warnings.coolant > 0 then
    for _, slot in ipairs(warnings.coolant) do
      local count = tr.transferItem(reactorChamberSide,meInterfaceSide,1,slot,9)
      if count and count > 0 then
        print("成功取出冷却剂槽位 " .. slot)
      else
        print("取出冷却剂槽位 " .. slot .. " 失败！")
      end
      sleep(0.5)  -- 等待0.5秒
    end
  end
end

local function main()
  while true do
    if isRedstoneInputActive() then
      print("检测到红石输入信号，开始检查反应堆槽位物品状态...")
      -- 首先检查反应堆槽位中的物品情况
      local chamberOK, warnings = checkReactorChamber()
      
      if chamberOK then
        print("反应堆物品状态正常，无需转移。激活反应堆...")
        activateReactor()
      else
        removeExhaustedItems(warnings)
        print("反应堆物品状态异常，存在以下问题：")
        if #warnings.fuel > 0 then
          print("缺少燃料棒的槽位：" .. table.concat(warnings.fuel, ", "))
        end
        if #warnings.coolant > 0 then
          print("缺少冷却剂的槽位：" .. table.concat(warnings.coolant, ", "))
        end
        print("开始执行物品转移操作...")
        local transfersOK = performTransfers(warnings)
        
        if transfersOK then
          print("物品转移操作成功，重新检查反应堆槽位物品状态...")
          chamberOK, warnings = checkReactorChamber()
          if chamberOK then
            sleep(0.5)  -- 等待0.5秒，确保物品转移生效
            print("检查完毕，反应堆物品状态正常。激活反应堆...")
            activateReactor()
          else
            print("物品转移后反应堆状态仍异常，停用反应堆并触发报警！")
            deactivateReactor()
            triggerAlarm()
          end
        else
          print("物品转移操作失败，停用反应堆并触发报警！")
          deactivateReactor()
          triggerAlarm()
        end
      end
    else
      print("无红石输入信号，保持反应堆停用状态...")
      deactivateReactor()
    end
    -- 根据需要设置检测周期
    computer.pullSignal(3)  -- 每3秒检查一次
  end
end


-- 启动程序
main()
