--
-- RecruitAFriend Configuration File
-- Adjust the values below to configure the Recruit-a-Friend module.
-- This file is loaded by RecruitAFriend.lua at startup.
--

------------------------------------------------------------------------------------------------
-- GENERAL SETTINGS
------------------------------------------------------------------------------------------------

-- Name of Eluna dB scheme
Config.customDbName = "ac_eluna"

-- set to 1 to print error messages to the console. Any other value including nil turns it off.
Config.printErrorsToConsole = 1

-- min GM level to bind accounts
Config.minGMRankForBind = 3

-- min GM level to read data
Config.minGMRankForRead = 2

-- max RAF duration in seconds. 2,592,000 = 30days
Config.maxRAFduration = 2592000

-- set to 1 to grant recruits always rested. Any other value including nil turns it off.
Config.grantRested = 1

-- set to 1 to print a login message. Any other value including nil turns it off.
Config.displayLoginMessage = 1

-- the level which a player must reach to reward it's recruiter and automatically end RAF
Config.targetLevel = 58

-- determines if the RAF link get removed when reaching the targetLevel
Config.endOnLevel = 1

-- set to 1 to grant always rested for premium past Config.targetLevel. Any other value including nil turns it off.
Config.premiumFeature = 0

-- maximum number of RAF related command uses before a kick. Includes summon requests.
Config.abuseTreshold = 1000

------------------------------------------------------------------------------------------------
-- SAME IP SETTINGS
------------------------------------------------------------------------------------------------

-- determines if there is a check for summoner and target being on the same Ip
Config.checkSameIp = 1

-- set to 1 to end RAF if linked accounts share an IP on the first infraction. Any other value including nil turns it off.
Config.endRAFOnSameIP = 0

-- set to 1 to block the recruiter reward when the "same IP" abuse check fails,
-- while still granting the rested experience bonus to the recruit.
-- Only applies when Config.endRAFOnSameIP is NOT 1 (i.e., the link is kept active).
Config.blockRewardOnSameIp = 0

-- should links on the same IP be removed automatically on startup / reload?
Config.AutoKillSameIPLinks = 1

------------------------------------------------------------------------------------------------
-- MAIL SETTINGS
------------------------------------------------------------------------------------------------

-- text for the mail to send when rewarding a recruiter
Config.mailText = "Hello Adventurer!\nYou've earned a reward for introducing your friends to Chromie.\nDon't stop here, there might be more goods to gain.\n\n"

-- modify's the mail database to prevent returning of rewards. Changes sender from character to creature. Config.senderGUID points to a creature if this is 1
Config.preventReturn = 1

-- GUID/ID of the player/creature. If Config.preventReturn = 1, you need to put creature ID. Else player GUID. 0 = No sender aka "From: Unknown". Creature 10667 is "Chromie".
Config.senderGUID = 10667

-- stationary used in the mail sent to the player. (41 Normal Mail, 61 GM/Blizzard Support, 62 Auction, 64 Valentines, 65 Christmas) Note: Use 62, 64, and 65 At your own risk.
Config.mailStationery = 41

------------------------------------------------------------------------------------------------
-- REWARDS
------------------------------------------------------------------------------------------------

-- rewards towards the recruiter for certain amounts of recruits who reached the target level. If not defined for a level, send the whole set of default potions
Config_rewards[1] = 56806    -- Mini Thor , Pet which is bound to account
Config_rewards[3] = 21841    -- Nether Cloth Bag - 16-slot
Config_rewards[5] = 13584    -- Diablos Stone, Pet which is bound to account
Config_rewards[10] = 39656   -- Tyrael's Hilt, Pet which is bound to account

-- amount of rewards per reward_level
Config_amounts[1] = 1
Config_amounts[3] = 1
Config_amounts[5] = 1
Config_amounts[10] = 1

-- default rewards if nothing is set in Config_rewards for a certain level. May be changed. May NOT be removed.
Config_defaultRewards[1] = 13454  -- Battle elixir spellpower
Config_defaultRewards[2] = 13452  -- Battle elixir agility
Config_defaultRewards[3] = 13453  -- Battle elixir strength
Config_defaultRewards[4] = 5634   -- Potion of Free Action

Config_defaultAmounts[1] = 10
Config_defaultAmounts[2] = 10
Config_defaultAmounts[3] = 10
Config_defaultAmounts[4] = 9

------------------------------------------------------------------------------------------------
-- ALLOWED MAPS FOR SUMMONING
------------------------------------------------------------------------------------------------

-- The following are the allowed maps to summon to. Additional maps can be added with a table.insert() line.
-- Remove or comment all table.insert below to forbid summoning
-- To change the allowed maps, first clear the table, then add your desired maps:
-- Config_maps = {}

-- Eastern kingdoms
table.insert(Config_maps, 0)
-- Kalimdor
table.insert(Config_maps, 1)
-- Outland
table.insert(Config_maps, 530)
-- Northrend
--table.insert(Config_maps, 571)
