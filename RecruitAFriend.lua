--
-- Created by IntelliJ IDEA.
-- User: Silvia
-- Date: 08/03/2021
-- Time: 20:39
-- To change this template use File | Settings | File Templates.
-- Originally created by Honey for Azerothcore
-- requires ElunaLua module


-- This module allows players to connect accounts with their friends to gain benefits
------------------------------------------------------------------------------------------------
-- ADMIN GUIDE:  -  compile the core with ElunaLua module
--               -  adjust config in this file
--               -  add this script to ../lua_scripts/
--               -  use the given commands via SOAP from the website to add/remove links (requires changes to acore-cms):
--               -  bind a recruiter: .bindraf $newRecruitId $existingRecruiterId
------------------------------------------------------------------------------------------------
-- PLAYER GUIDE: - as the new player(RECRUIT): make yourself RECRUITED by selecting your recruiters ID during account creation on the website
--               - as the existing player (RECRUITER): summon your friend with ".raf summon $FriendsCharacterName"
--               - discover your own account id by typing ".raf help"
--               - once the RECRUIT reaches a level set in config, the RECRUITER receives a reward.
--               - same IP possibly restricts or removes the bind (sorry families, roommates and the like)
------------------------------------------------------------------------------------------------

-- Global tables required for external config file (RecruitAFriend_conf.lua) access
Config = {}
Config_maps = {}
Config_rewards = {}
Config_amounts = {}
Config_defaultRewards = {}
Config_defaultAmounts = {}

-- Default configuration values (can be overridden by RecruitAFriend_conf.lua)
Config.customDbName = "ac_eluna"
Config.printErrorsToConsole = 1
Config.minGMRankForBind = 3
Config.minGMRankForRead = 2
Config.maxRAFduration = 2592000
Config.grantRested = 1
Config.displayLoginMessage = 1
Config.targetLevel = 58
Config.endOnLevel = 1
Config.premiumFeature = 0
Config.abuseTreshold = 1000
Config.checkSameIp = 1
Config.endRAFOnSameIP = 0
Config.blockRewardOnSameIp = 0
Config.mailText = "Hello Adventurer!\nYou've earned a reward for introducing your friends to Chromie.\nDon't stop here, there might be more goods to gain.\n\n"
Config.preventReturn = 1
Config.senderGUID = 10667
Config.mailStationery = 41
Config.AutoKillSameIPLinks = 1
Config_rewards[1] = 56806
Config_rewards[3] = 21841
Config_rewards[5] = 13584
Config_rewards[10] = 39656
Config_amounts[1] = 1
Config_amounts[3] = 1
Config_amounts[5] = 1
Config_amounts[10] = 1
Config_defaultRewards[1] = 13454
Config_defaultRewards[2] = 13452
Config_defaultRewards[3] = 13453
Config_defaultRewards[4] = 5634
Config_defaultAmounts[1] = 10
Config_defaultAmounts[2] = 10
Config_defaultAmounts[3] = 10
Config_defaultAmounts[4] = 9
table.insert(Config_maps, 0)
table.insert(Config_maps, 1)
table.insert(Config_maps, 530)

-- Load external configuration file (overrides defaults above)
do
    local scriptPath = debug.getinfo(1, "S").source:sub(2):match("(.*[\\/])") or ""
    local confPath = scriptPath .. "RecruitAFriend_conf.lua"
    local f = io.open(confPath, "r")
    if f then
        f:close()
        -- Reset map table before loading config so config file controls allowed maps
        Config_maps = {}
        dofile(confPath)
        if Config.printErrorsToConsole == 1 then
            PrintInfo("RAF: Loaded configuration from RecruitAFriend_conf.lua")
        end
    else
        PrintInfo("RAF: RecruitAFriend_conf.lua not found. Using default configuration.")
    end
end
------------------------------------------
-- NO ADJUSTMENTS REQUIRED BELOW THIS LINE
------------------------------------------

local PLAYER_EVENT_ON_LOGIN = 3          -- (event, player)
local PLAYER_EVENT_ON_LEVEL_CHANGE = 13  -- (event, player, oldLevel)
local PLAYER_EVENT_ON_COMMAND = 42       -- (event, player, command) - player is nil if command used from console. Can return false

CharDBQuery('CREATE DATABASE IF NOT EXISTS `'..Config.customDbName..'`;');
CharDBQuery('CREATE TABLE IF NOT EXISTS `'..Config.customDbName..'`.`recruit_a_friend_links` (`account_id` INT NOT NULL, `recruiter_account` INT DEFAULT 0, `time_stamp` INT DEFAULT 0, `ip_abuse_counter` INT DEFAULT 0, `kick_counter` INT DEFAULT 0, `complete` TINYINT DEFAULT 0, `comment` varchar(255) DEFAULT "", PRIMARY KEY (`account_id`) );');
CharDBQuery('CREATE TABLE IF NOT EXISTS `'..Config.customDbName..'`.`recruit_a_friend_rewards` (`recruiter_account` INT DEFAULT 0, `reward_level` INT DEFAULT 0, PRIMARY KEY (`recruiter_account`) );');

--sanity check
if Config_defaultRewards[1] == nil or Config_defaultRewards[2] == nil or Config_defaultRewards[3] == nil or Config_defaultRewards[4] == nil then
    PrintError("RAF: The Config_defaultRewards value was removed for at least one flag ([1]-[4] are required.)")
end

if Config.AutoKillSameIPLinks == 1 then
    CharDBQuery('UPDATE `'..Config.customDbName..'`.recruit_a_friend_links SET time_stamp = 0 WHERE ip_abuse_counter > 5 AND time_stamp > 1;')
end

--globals:
RAF_xpPerLevel = {}
RAF_recruiterAccount = {}
RAF_timeStamp = {}
RAF_abuseCounter = {}
RAF_sameIpCounter = {}
RAF_kickCounter = {}
RAF_lastIP = {}
RAF_rewardLevel = {}
RAF_complete = {}

local function RAF_numeralise(n)
    n = tostring(n)
    if string.sub(n, -1) == "1" then
        n = n.."st"
    elseif string.sub(n, -1) == "2" then
        n = n.."nd"
    elseif string.sub(n, -1) == "3" then
        n = n.."rd"
    else
        n = n.."th"
    end
    return n
end

-- unix to date conversion based on http://www.ethernut.de/api/gmtime_8c_source.html
local floor=math.floor

local DSEC=24*60*60 -- secs in a day
local YSEC=365*DSEC -- secs in a year
local LSEC=YSEC+DSEC    -- secs in a leap year
local FSEC=4*YSEC+DSEC  -- secs in a 4-year interval
local BASE_DOW=4    -- 1970-01-01 was a Thursday
local BASE_YEAR=1970    -- 1970 is the base year

local _days={
    -1, 30, 58, 89, 119, 150, 180, 211, 242, 272, 303, 333, 364
}
local _lpdays={}
for i=1,2  do _lpdays[i]=_days[i]   end
for i=3,13 do _lpdays[i]=_days[i]+1 end

local function RAF_gmtime(t)
    local y,j,m,d,w,h,n,s
    local mdays=_days
    s=t
    -- First calculate the number of four-year-interval, so calculation
    -- of leap year will be simple. Btw, because 2000 IS a leap year and
    -- 2100 is out of range, this formula is so simple.
    y=floor(s/FSEC)
    s=s-y*FSEC
    y=y*4+BASE_YEAR         -- 1970, 1974, 1978, ...
    if s>=YSEC then
        y=y+1           -- 1971, 1975, 1979,...
        s=s-YSEC
        if s>=YSEC then
            y=y+1       -- 1972, 1976, 1980,... (leap years!)
            s=s-YSEC
            if s>=LSEC then
                y=y+1   -- 1971, 1975, 1979,...
                s=s-LSEC
            else        -- leap year
                mdays=_lpdays
            end
        end
    end
    j=floor(s/DSEC)
    s=s-j*DSEC
    local m=1
    while mdays[m]<j do m=m+1 end
    m=m-1
    local d=j-mdays[m]
    -- Calculate day of week. Sunday is 0
    w=(floor(t/DSEC)+BASE_DOW)%7
    -- Calculate the time of day from the remaining seconds
    h=floor(s/3600)
    s=s-h*3600
    n=floor(s/60)
    s=s-n*60
    d = RAF_numeralise(d)
    return(({"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"})[m]..', '..d..' '..y..' '..h..':'..n..':'..s)
end

local function RAF_PreventReturn(playerGUID)
    if Config.preventReturn == 1 then
        CharDBExecute('UPDATE `mail` SET `messageType` = 3 WHERE `sender` = '..Config.senderGUID..' AND `receiver` = '..playerGUID..' AND `messageType` = 0;')
    end
end

local function RAF_cleanup()
    --todo: check variables for required cleanups
    --set all non local runtime variables to nil
end

local function RAF_splitString(inputstr, seperator)
    if seperator == nil then
        seperator = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..seperator.."]+)") do
        table.insert(t, str)
    end
    return t
end

local function RAF_hasValue (tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

local function RAF_hasIndex (tab, val)
    for index, value in ipairs(tab) do
        if index == val then
            return true
        end
    end
    return false
end

local function RAF_grantRestedXP(player)
    if Config.grantRested == 1 then
        if _G.ChallengeModes == nil or not _G.ChallengeModes:isPlayerEnlisted(player) then
            player:SetRestBonus(RAF_xpPerLevel[player:GetLevel()])
        end
    end
end

local function RAF_checkAbuse(accountId)
    if RAF_abuseCounter[accountId] == nil then
        RAF_abuseCounter[accountId] = 1
    else
        RAF_abuseCounter[accountId] = RAF_abuseCounter[accountId] + 1
    end

    if RAF_abuseCounter[accountId] > Config.abuseTreshold then
        return true
    end
    return false
end

local function RAF_command(event, player, command, chatHandler)
    local commandArray = {}
    -- split the command variable into several strings which can be compared individually
    commandArray = RAF_splitString(command)

    if commandArray[1] ~= "bindraf" and commandArray[1] ~= "forcebindraf" and commandArray[1] ~= "raf" then
        return
    end

    if commandArray[2] ~= nil then
        commandArray[2] = commandArray[2]:gsub("[';\\, ]", "")
        if commandArray[3] ~= nil then
            commandArray[3] = commandArray[3]:gsub("[';\\, ]", "")
        end
    end

    if commandArray[1] == "bindraf" then

        if player ~= nil then
            if player:GetGMRank() < Config.minGMRankForBind then
                if Config.printErrorsToConsole == 1 then PrintInfo("Account "..player:GetAccountId().." tried the .bindraf command without sufficient rights.") end
                return
            end
        end

        local commandSource
        if player == nil then
            commandSource = "worldserver console"
        else
            commandSource = "account id: "..tostring(player:GetAccountId())
        end
        -- GM/SOAP command to bind from console or ingame commands
        if commandArray[2] ~= nil and commandArray[3] ~= nil then
            local accountId = tonumber(commandArray[2])
            if RAF_recruiterAccount[accountId] == nil then
                RAF_recruiterAccount[accountId] = tonumber(commandArray[3])
                RAF_timeStamp[accountId] = (tonumber(tostring(GetGameTime())))
                CharDBExecute('REPLACE INTO `'..Config.customDbName..'`.`recruit_a_friend_links` VALUES ('..accountId..', '..RAF_recruiterAccount[accountId]..', '..RAF_timeStamp[accountId]..', 0, 0, 0, "");')
                chatHandler:SendSysMessage(commandSource.." has succesfully used the .bindraf command on recruit "..accountId.." and recruiter "..RAF_recruiterAccount[accountId]..".")
            else
                chatHandler:SendSysMessage("The selected account "..accountId.." is already recruited by "..RAF_recruiterAccount[accountId]..".")
            end
        else
            chatHandler:SendSysMessage("Admin/GM Syntax: .bindraf $recruit $recruiter binds the accounts to each other.")
            chatHandler:SendSysMessage("Admin/GM Syntax: .forcebindraf $recruit $recruiter same as .bindraf but ignores past binds. Previously unbound, succesful or timed out doesn't matter.")
        end
        RAF_cleanup()
        return false

    elseif commandArray[1] == "forcebindraf" then

        if player ~= nil then
            if player:GetGMRank() < Config.minGMRankForBind then
                if Config.printErrorsToConsole == 1 then PrintInfo("Account "..player:GetAccountId().." tried the .forcebindraf command without sufficient rights.") end
                return
            end
        end

        local commandSource
        if player == nil then
            commandSource = "worldserver console"
        else
            commandSource = "account id: "..tostring(player:GetAccountId())
        end
        -- GM/SOAP command to force bind from console or ingame commands
        if commandArray[2] ~= nil and commandArray[3] ~= nil then
            local accountId = tonumber(commandArray[2])
            RAF_recruiterAccount[accountId] = tonumber(commandArray[3])
            RAF_timeStamp[accountId] = (tonumber(tostring(GetGameTime())))
            CharDBExecute('REPLACE INTO `'..Config.customDbName..'`.`recruit_a_friend_links` VALUES ('..accountId..', '..RAF_recruiterAccount[accountId]..', '..RAF_timeStamp[accountId]..', 0, 0, 0, "");')
            chatHandler:SendSysMessage(commandSource.." has succesfully used the .forcebindraf command on recruit "..accountId.." and recruiter "..RAF_recruiterAccount[accountId]..".")
        else
            chatHandler:SendSysMessage("Admin/GM Syntax: .bindraf $recruit $recruiter binds the accounts to each other.")
            chatHandler:SendSysMessage("Admin/GM Syntax: .forcebindraf $recruit $recruiter same as .bindraf but ignores past binds. Previously unbound, succesful or timed out doesn't matter.")
        end
        RAF_cleanup()
        return false


    elseif commandArray[1] == "raf" then

        if player ~= nil then
            if RAF_checkAbuse(player:GetAccountId()) == true then
                local recruitId
                player:KickPlayer()
                for index, value in pairs(RAF_recruiterAccount) do
                    if value == player:GetAccountId() then
                        recruitId = index
                    end
                end
                if RAF_kickCounter[recruitId] == nil then
                    RAF_kickCounter[recruitId] = 1
                else
                    RAF_kickCounter[recruitId] = RAF_kickCounter[recruitId] + 1
                    CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_links` SET `kick_counter` = '..RAF_kickCounter[recruitId]..' WHERE `account_id` = '..recruitId..';')
                    if Config.printErrorsToConsole == 1 then PrintError("RAF: account id "..player:GetAccountId().." was kicked because of too many .raf commands.") end
                end
            end
        end

        -- list all accounts recruited by this account
        if commandArray[2] == "list" then

            if player == nil then
                chatHandler:SendSysMessage("'.raf list' is not meant to be used from the console.")
                return false
            end

            -- print all recruits bound to this account by charname
            local idList
            for index, value in pairs(RAF_recruiterAccount) do
                if value == player:GetAccountId() then
                    if RAF_timeStamp[index] > 1 then
                        if idList == nil then
                            idList = index
                        else
                            idList = idList.." "..index
                        end
                    end
                end
            end
            if idList == nil then
                idList = "none"
            end


            chatHandler:SendSysMessage("Your current recruits are: "..idList)
            RAF_cleanup()
            return false

        elseif commandArray[2] == "summon" then
            if player == nil then
                chatHandler:SendSysMessage("'.raf summon' is not meant to be used from the console.")
                return false
            end

            if player:IsFlying() then
                chatHandler:SendSysMessage("'.raf summon' can not be used while flying.")
                return false
            end

            if commandArray[3] == nil then
                chatHandler:SendSysMessage("'.raf summon' requires the name of the target. Use '.raf summon $Name'")
                return false
            else
                commandArray[3] = commandArray[3]:gsub("^%l", string.upper)
            end

            -- check if the target is a recruit of the player
            local summonPlayer = GetPlayerByName(commandArray[3])
            if summonPlayer == nil then
                chatHandler:SendSysMessage("Target not found. Check spelling and capitalization.")
                RAF_cleanup()
                return false
            end

            if RAF_recruiterAccount[summonPlayer:GetAccountId()] ~= player:GetAccountId() then
                chatHandler:SendSysMessage("The requested player is not your recruit.")
                RAF_cleanup()
                return false
            end

            if RAF_timeStamp[summonPlayer:GetAccountId()] == 0 or RAF_timeStamp[summonPlayer:GetAccountId()] == 1 then
                chatHandler:SendSysMessage("The requested player is not your recruit anymore.")
                RAF_cleanup()
                return false
            end

            -- do the zone/combat checks and possibly summon
            local mapId = player:GetMapId()
            -- allow to proceed if the player is on one of the maps listed above
            if RAF_hasValue(Config_maps, mapId) then
                --allow to proceed if the player is not in combat
                if not player:IsInCombat() then
                    local group = player:GetGroup()
                    if group == nil then
                        chatHandler:SendSysMessage("You must be in a party or raid to summon your recruit.")
                        return false
                    end
                    local groupPlayers = group:GetMembers()
                    for _, v in pairs(groupPlayers) do
                        if v:GetName() == commandArray[3] then
                            if player:GetPlayerIP() == v:GetPlayerIP() and Config.checkSameIp == 1 and RAF_timeStamp[summonPlayer:GetAccountId()] >= 2 then
                                chatHandler:SendSysMessage("Possible abuse detected. Aborting. This action is logged.")
                                if RAF_sameIpCounter[summonPlayer:GetAccountId()] == nil then
                                    RAF_sameIpCounter[summonPlayer:GetAccountId()] = 1
                                    CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_links` SET ip_abuse_counter = '..RAF_sameIpCounter[summonPlayer:GetAccountId()]..' WHERE `account_id` = '..summonPlayer:GetAccountId()..';')
                                    RAF_cleanup()
                                    return false
                                else
                                    RAF_sameIpCounter[summonPlayer:GetAccountId()] = RAF_sameIpCounter[summonPlayer:GetAccountId()] + 1
                                    CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_links` SET ip_abuse_counter = '..RAF_sameIpCounter[summonPlayer:GetAccountId()]..' WHERE `account_id` = '..summonPlayer:GetAccountId()..';')
                                    RAF_cleanup()
                                    return false
                                end
                            end
                            v:SummonPlayer(player)
                        end
                    end
                else
                    chatHandler:SendSysMessage("Summoning is not possible in combat.")
                end
                return false
            else
                chatHandler:SendSysMessage("Summoning is not possible here.")
            end
            return false

        elseif commandArray[2] == "unbind" and commandArray[3] == nil then
            if player == nil then
                chatHandler:SendSysMessage("Console can not have recruits to remove.")
                return false
            end

            local accountId = player:GetAccountId()
            if RAF_recruiterAccount[accountId] ~= nil and RAF_timeStamp[accountId] > 1 then
                RAF_timeStamp[accountId] = 0
                CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_links` SET time_stamp = 0 WHERE `account_id` = '..accountId..';')
                chatHandler:SendSysMessage("Your Recruit-a-friend link was removed by choice.")
            else
                chatHandler:SendSysMessage("Your account is not recruited (anymore).")
            end

            return false

        elseif commandArray[2] == "help" or commandArray[2] == nil then
            if player == nil then
                chatHandler:SendSysMessage("Admin/GM Syntax: .bindraf $recruit $recruiter binds the accounts to each other.")
                chatHandler:SendSysMessage("Admin/GM Syntax: .forcebindraf $recruit $recruiter same as .bindraf but ignores past binds. Previously unbound, succesful or timed out doesn't matter.")
            else
                chatHandler:SendSysMessage("Your account id is: "..player:GetAccountId())
            end

            chatHandler:SendSysMessage("Syntax to list all recruits: .raf list")
            chatHandler:SendSysMessage("Syntax to summon the recruit: .raf summon $FriendsCharacterName")
            chatHandler:SendSysMessage("Only the recruiter can summon the recruit. The recruit can NOT summon. You must be in a party/raid with each other.")
            RAF_cleanup()
            return false

        elseif commandArray[2] == "lookup" then
            if player == nil or player:GetGMRank() >= Config.minGMRankForRead then
                if commandArray[3] == nil then
                    chatHandler:SendSysMessage('Expected syntax: .raf lookup $accountId')
                    return false
                end

                commandArray[3] = tonumber(commandArray[3])
                if RAF_recruiterAccount[commandArray[3]] ~= nil then

                    chatHandler:SendSysMessage('RAF Data for account '..commandArray[3]..':')
                    chatHandler:SendSysMessage('Recruiter account: '..RAF_recruiterAccount[commandArray[3]])

                    if RAF_timeStamp[commandArray[3]] == 0 then
                        chatHandler:SendSysMessage('The RAF link was removed or expired.')
                    elseif RAF_timeStamp[commandArray[3]] == 1 then
                        chatHandler:SendSysMessage('The RAF link was succesful but is over.')
                    elseif RAF_timeStamp[commandArray[3]] == -1 then
                        chatHandler:SendSysMessage('The RAF link is permanently activated for a contributor.')
                    else
                        chatHandler:SendSysMessage('The RAF link is active and was activated at '..RAF_gmtime(RAF_timeStamp[commandArray[3]]))
                    end

                    if RAF_sameIpCounter[commandArray[3]] then
                        chatHandler:SendSysMessage('Same IP counter: '..RAF_sameIpCounter[commandArray[3]])
                    else
                        chatHandler:SendSysMessage('Same IP counter: 0')
                    end

                    if RAF_kickCounter[commandArray[3]] then
                        chatHandler:SendSysMessage('Kick counter: '..RAF_kickCounter[commandArray[3]])
                    else
                        chatHandler:SendSysMessage('Kick counter: 0')
                    end

                    if RAF_rewardLevel[commandArray[3]] ~=nil then
                        chatHandler:SendSysMessage('Reward Level: '..RAF_rewardLevel[commandArray[3]])
                    else
                        chatHandler:SendSysMessage('Reward Level: 0')
                    end
                else
                    chatHandler:SendSysMessage('Account with ID '..commandArray[3]..' has not been recruited.')
                end
                return false
            end
        end
    end
end

local function RAF_login(event, player)
    local accountId = player:GetAccountId()

    -- display login message
    if Config.displayLoginMessage == 1 then
        player:SendBroadcastMessage("This server features a Recruit-a-friend module. Type .raf for help.")
    end

    RAF_lastIP[accountId] = player:GetPlayerIP()

    -- check for an existing RAF connection when a RECRUIT or RECRUITER logs in
    local recruiterId = RAF_recruiterAccount[player:GetAccountId()]
    if recruiterId == nil and RAF_hasIndex(RAF_recruiterAccount, player:GetAccountId()) == false then
        return false
    end

    -- check for RAF timeout on login of the RECRUIT, possibly remove the link
    if RAF_timeStamp[accountId] <= 1 then
        if RAF_timeStamp[accountId] == -1 and Config.premiumFeature == 1 then
            if _G.ChallengeModes ~= nil and _G.ChallengeModes:isPlayerEnlisted(player) then
                return false
            end
            player:SetRestBonus(RAF_xpPerLevel[player:GetLevel()])
            return false
        else
            return false
        end
    end

    --reset abuse counter
    RAF_abuseCounter[accountId] = 0

    local targetDuration = RAF_timeStamp[accountId] + Config.maxRAFduration
    if (tonumber(tostring(GetGameTime()))) > targetDuration then
        RAF_timeStamp[accountId] = 0
        CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_links` SET time_stamp = 0 WHERE `account_id` = '..accountId..';')
        player:SendBroadcastMessage("Your RAF link has reached the time-limit and expired.")
        return false
    end

    -- add 1 full level of rested at login while in RAF
    RAF_grantRestedXP(player)

    -- same IP check
    local recruiterId = RAF_recruiterAccount[accountId]
    if RAF_lastIP[accountId] == RAF_lastIP[recruiterId] then
        if Config.endRAFOnSameIP == 1 then
            player:SendBroadcastMessage("The RAF link was removed")
            CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_links` SET time_stamp = 0 WHERE `account_id` = '..accountId..';')
            RAF_timeStamp[accountId] = 0
        else
            player:SendBroadcastMessage("Recruit a friend: Possible abuse detected. This action is logged.")
            if RAF_sameIpCounter[accountId] == nil then
                RAF_sameIpCounter[accountId] = 1
            else
                RAF_sameIpCounter[accountId] = RAF_sameIpCounter[accountId] + 1
            end
            CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_links` SET ip_abuse_counter = '..RAF_sameIpCounter[accountId]..' WHERE `account_id` = '..accountId..';')
        end
    end

    RAF_cleanup()
    return false
end

local function GrantReward(recruiterId)

    local recruiterCharacter
    if RAF_rewardLevel[recruiterId] == nil then
        RAF_rewardLevel[recruiterId] = 1
        CharDBExecute('REPLACE INTO `'..Config.customDbName..'`.`recruit_a_friend_rewards` VALUES ('..recruiterId..', '..RAF_rewardLevel[recruiterId]..');')
    else
        RAF_rewardLevel[recruiterId] = RAF_rewardLevel[recruiterId] + 1
        CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_rewards` SET reward_level = '..RAF_rewardLevel[recruiterId]..' WHERE `recruiter_account` = '..recruiterId..';')
    end

    local Data_SQL = CharDBQuery('SELECT `guid` FROM `characters` WHERE `account` = '..recruiterId..' LIMIT 1;')
    if Data_SQL ~= nil then
        recruiterCharacter = Data_SQL:GetUInt32(0)
    else
        if Config.printErrorsToConsole == 1 then PrintError("RAF: No character found on recruiter account with id "..recruiterId..", which was eligable for a RAF reward of level "..RAF_rewardLevel[recruiterId]..".") end
        return
    end

    --reward the recruiter
    local rewardLevel = RAF_rewardLevel[recruiterId]
    if Config_rewards[rewardLevel] == nil then
        --send the default set
        SendMail("RAF reward level "..rewardLevel, Config.mailText, recruiterCharacter, Config.senderGUID, Config.mailStationery, 0, 0, 0, Config_defaultRewards[1], Config_defaultAmounts[1], Config_defaultRewards[2], Config_defaultAmounts[2], Config_defaultRewards[3], Config_defaultAmounts[3], Config_defaultRewards[4], Config_defaultAmounts[4])
    else
        SendMail("RAF reward level "..rewardLevel, Config.mailText, recruiterCharacter, Config.senderGUID, Config.mailStationery, 0, 0, 0, Config_rewards[rewardLevel], Config_amounts[rewardLevel])
    end
    RAF_PreventReturn(recruiterCharacter)
end

local function RAF_levelChange(event, player, oldLevel)

    local accountId = player:GetAccountId()
    -- check for RAF timeout on login of the RECRUIT, possibly remove the link
    if RAF_recruiterAccount[accountId] == nil or RAF_timeStamp[accountId] <= 1 then
        if RAF_timeStamp[accountId] == -1 and Config.premiumFeature == 1 then
            if _G.ChallengeModes ~= nil and _G.ChallengeModes:isPlayerEnlisted(player) then
                return false
            end
            player:SetRestBonus(RAF_xpPerLevel[oldLevel + 1])
            return false
        else
            return false
        end
    end

    if Config.endOnLevel == 1 then
        if oldLevel + 1 >= Config.targetLevel then
            -- set time_stamp to 1 and Grant rewards
            RAF_timeStamp[accountId] = 1
            CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_links` SET time_stamp = 1 WHERE `account_id` = '..accountId..';')
            if Config.blockRewardOnSameIp == 1 and RAF_sameIpCounter[accountId] ~= nil and RAF_sameIpCounter[accountId] > 0 then
                player:SendBroadcastMessage("Your RAF link has reached the level-limit but the reward was blocked due to same IP usage.")
                RAF_grantRestedXP(player)
            else
                GrantReward(RAF_recruiterAccount[accountId])
                player:SendBroadcastMessage("Your RAF link has reached the level-limit. Your recruiter has earned a reward. Go and bring your friends, too!")
            end
            return false
        end
    else
        if oldLevel + 1 >= Config.targetLevel then
            -- grant rewards
            if RAF_complete[accountId] == 0 then
                CharDBExecute('UPDATE `'..Config.customDbName..'`.`recruit_a_friend_links` SET `complete` = 1 WHERE `account_id` = '..accountId..';')
                if Config.blockRewardOnSameIp == 1 and RAF_sameIpCounter[accountId] ~= nil and RAF_sameIpCounter[accountId] > 0 then
                    player:SendBroadcastMessage("Your RAF link has reached the level-limit but the reward was blocked due to same IP usage.")
                    RAF_grantRestedXP(player)
                else
                    GrantReward(RAF_recruiterAccount[accountId])
                    player:SendBroadcastMessage("Your RAF link has reached the level-limit. Your recruiter has earned a reward. Go and bring your friends, too!")
                end
                return false
            end
        end
    end

    local recruiterId = RAF_recruiterAccount[accountId]
    if recruiterId == nil then
        return false
    end

    -- add 1 full level of rested at levelup while in RAF and not at maxlevel with Player:SetRestBonus( restBonus )
    RAF_grantRestedXP(player)
end

--INIT sequence:
--global table which reads the required XP per level one single time on load from the db instead of one value every levelup event
local RAF_Data_SQL
local RAF_row = 1
local RAF_Data_SQL = WorldDBQuery('SELECT Experience FROM player_xp_for_level WHERE Level <= 80;')
if RAF_Data_SQL ~= nil then
    repeat
        RAF_xpPerLevel[RAF_row] = RAF_Data_SQL:GetUInt32(0)
        RAF_row = RAF_row + 1
    until not RAF_Data_SQL:NextRow()
else
    PrintError("RAF: Error reading player_xp_for_level from tha database.")
end
RAF_Data_SQL = nil
RAF_row = nil

--global table which stores already granted rewards
local RAF_Data_SQL
local RAF_id
RAF_Data_SQL = CharDBQuery('SELECT * FROM `'..Config.customDbName..'`.`recruit_a_friend_rewards`;')
if RAF_Data_SQL ~= nil then
    repeat
        RAF_id = tonumber(RAF_Data_SQL:GetUInt32(0))
        RAF_rewardLevel[RAF_id] = tonumber(RAF_Data_SQL:GetUInt32(1))
    until not RAF_Data_SQL:NextRow()
else
    PrintError("RAF: Found no granted rewards in the recruit_a_friend_rewards table. Possibly there are none yet.")
end

--global table which stores all RAF links
local RAF_Data_SQL
local RAF_id
RAF_Data_SQL = CharDBQuery('SELECT * FROM `'..Config.customDbName..'`.`recruit_a_friend_links`;')

if RAF_Data_SQL ~= nil then
    repeat
        RAF_id = tonumber(RAF_Data_SQL:GetUInt32(0))
        RAF_recruiterAccount[RAF_id] = tonumber(RAF_Data_SQL:GetUInt32(1))
        RAF_timeStamp[RAF_id] = tonumber(RAF_Data_SQL:GetInt32(2))
        RAF_sameIpCounter[RAF_id] = RAF_Data_SQL:GetUInt32(3)
        RAF_kickCounter[RAF_id] = tonumber(RAF_Data_SQL:GetUInt32(4))
        RAF_complete[RAF_id] = tonumber(RAF_Data_SQL:GetUInt32(5))
    until not RAF_Data_SQL:NextRow()
else
    PrintError("RAF: Found no linked accounts in the recruit_a_friend table. Possibly there are none yet.")
end

RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, RAF_command)
RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, RAF_login)
RegisterPlayerEvent(PLAYER_EVENT_ON_LEVEL_CHANGE, RAF_levelChange)
