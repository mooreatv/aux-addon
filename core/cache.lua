select(2, ...) 'aux.util.info'

local T = require 'T'
local aux = require 'aux'
local persistence = require 'aux.util.persistence'

local MIN_ITEM_ID = 1
local MAX_ITEM_ID = 30000

local items_schema = {'tuple', '#', {name='string'}, {link='string'}, {quality='number'}, {level='number'}, {requirement='number'}, {class='string'}, {subclass='string'}, {slot='string'}, {max_stack='number'}, {texture='string'}, {sell_price='number'}}
local merchant_buy_schema = {'tuple', '#', {unit_price='number'}, {limited='boolean'}}

function aux.handle.LOAD()
    aux.event_listener('GET_ITEM_INFO_RECEIVED', on_get_item_info_received)
    fetch_item_data()

	aux.event_listener('MERCHANT_SHOW', on_merchant_show)
	aux.event_listener('MERCHANT_CLOSED', on_merchant_closed)
	aux.event_listener('MERCHANT_UPDATE', on_merchant_update)
end

do
	local characters = {}
	function M.is_player(name)
		return not not characters[name]
	end
	function aux.handle.LOAD()
		characters = aux.realm_data.characters
		for k, v in pairs(characters) do
			if GetTime() > v + 60 * 60 * 24 * 30 then
				characters[k] = nil
			end
		end
		characters[UnitName'player'] = GetTime()
	end
end

do
	local incomplete_buy_data
	function on_merchant_show()
		incomplete_buy_data = not merchant_buy_scan()
	end
	function on_merchant_closed()
		incomplete_buy_data = false
	end
	function on_merchant_update()
		if incomplete_buy_data then
			incomplete_buy_data = not merchant_buy_scan()
		end
	end
end

function merchant_loaded()
	for i = 1, GetMerchantNumItems() do
		if not GetMerchantItemLink(i) then
			return false
		end
	end
	return true
end

function M.merchant_buy_info(item_id)
	local buy_info
	if aux.account_data.merchant_buy[item_id] then
		buy_info = persistence.read(merchant_buy_schema, aux.account_data.merchant_buy[item_id])
	end
	return buy_info and buy_info.unit_price, buy_info and buy_info.limited
end

function M.item_info(item_id)
	local data_string = aux.account_data.items[item_id]
	if data_string then
		return aux.copy(persistence.read(items_schema, data_string))
	end
end

function M.item_id(item_name)
	return aux.account_data.item_ids[strlower(item_name)]
end

function merchant_buy_scan()
	local incomplete_data
	for i = 1, GetMerchantNumItems() do
		local _, _, price, count, stock = GetMerchantItemInfo(i)
		local link = GetMerchantItemLink(i)
		if link then
			local item_id = parse_link(link)
			local new_unit_price, new_limited = price / count, stock >= 0
			if aux.account_data.merchant_buy[item_id] then
				local buy_info = persistence.read(merchant_buy_schema, aux.account_data.merchant_buy[item_id])

				local unit_price
				if buy_info.limited and not new_limited then
					unit_price = new_unit_price
				elseif new_limited and not buy_info.limited then
					unit_price = buy_info.unit_price
				else
					unit_price = min(buy_info.unit_price, new_unit_price)
				end

                aux.account_data.merchant_buy[item_id] = persistence.write(merchant_buy_schema, T.map(
					'unit_price', unit_price,
					'limited', buy_info.limited and new_limited
				))
			else
				aux.account_data.merchant_buy[item_id] = persistence.write(merchant_buy_schema, T.map(
					'unit_price', new_unit_price,
					'limited', new_limited
				))
			end
		else
			incomplete_data = true
		end
	end

	return not incomplete_data
end

function process_item(item_id)
    local itemstring = 'item:' .. item_id
    local name, link, quality, level, requirement, class, subclass, max_stack, slot, texture, sell_price = GetItemInfo(itemstring)

    if name then
        aux.account_data.item_ids[strlower(name)] = item_id
        aux.account_data.items[item_id] = persistence.write(items_schema, T.map(
            'name', name,
            'link', link,
            'quality', quality,
            'level', level,
            'requirement', requirement,
            'class', class,
            'subclass', subclass,
            'slot', slot,
            'max_stack', max_stack,
            'texture', texture,
            'sell_price', sell_price
        ))
        local tooltip = tooltip('link', itemstring)
        if auctionable(tooltip, quality) then
            tinsert(aux.account_data.auctionable_items, strlower(name))
        end
        return true
    end
end

do
    local requested_item_id

    function fetch_item_data(item_id)
        item_id = item_id or MIN_ITEM_ID

        while aux.account_data.items[item_id] or aux.account_data.unused_item_ids[item_id] do
            item_id = item_id + 1
        end

        if item_id > MAX_ITEM_ID then
            return
        end

        if process_item(item_id) then
            fetch_item_data(item_id + 1)
        else
            requested_item_id = item_id
        end
    end

    function on_get_item_info_received(_, item_id, success)
        if success then
            process_item(item_id)
        elseif success == nil then
            aux.account_data.unused_item_ids[item_id] = true
        end
        if item_id == requested_item_id then
            fetch_item_data(item_id + 1)
        end
    end
end