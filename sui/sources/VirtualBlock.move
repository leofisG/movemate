// SPDX-License-Identifier: UNLICENSED

/// @title VirtualBlock
/// @dev This module allows the creation of virtual blocks with transactions sorted by fees, turning transaction latency auctions into fee auctions.
/// Once you've created a new mempool (specifying a miner fee rate and a block time/delay), simply add entries to the block,
/// mine the entries (for a miner fee), and repeat. Extract mempool fees as necessary.
module Movemate::VirtualBlock {
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};

    use Econia::CritBit::{Self, CB};

    /// @notice Struct for a virtual block with entries sorted by bids.
    struct Mempool<BidAssetType, EntryType> {
        blocks: vector<CB<EntryType>>,
        current_block_bids: Coin<BidAssetType>,
        last_block_timestamp: u64,
        mempool_fees: Coin<BidAssetType>,
        miner_fee_rate: u64,
        block_time: u64
    }

    /// @notice Creates a new mempool (specifying miner fee rate and block time/delay).
    public fun new_mempool<BidAssetType, EntryType>(miner_fee_rate: u64, block_time: u64, ctx: &mut TxContext): Mempool<BidAssetType, EntryType> {
        Mempool<BidAssetType, EntryType> {
            blocks: Vector::singleton<CB<EntryType>>(CritBit::empty<EntryType>()),
            current_block_bids: coin::zero<BidAssetType>(ctx),
            last_block_timestamp: tx_context::epoch(ctx),
            mempool_fees: coin::zero<BidAssetType>(ctx),
            miner_fee_rate,
            block_time
        }
    }

    /// @notice Extracts all fees accrued by a mempool.
    public fun extract_mempool_fees<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>, ctx: &mut TxContext): Coin<BidAssetType> {
        coin::split(&mut mempool.mempool_fees, coin::value(&mempool.mempool_fees))
    }

    /// @notice Adds an entry to the latest virtual block.
    public fun add_entry<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>, entry: EntryType, bid: Coin<BidAssetType>) {
        // Add bid to block
        coin::join(&mut mempool.current_block_bids, bid);

        // Add entry to tree
        let block = Vector::borrow_mut(&mut mempool.blocks, Vector::length(&mempool.blocks) - 1);
        CritBit::insert(block, (coin::value(&bid) as u128), entry);
    }

    /// @notice Validates the block time and distributes fees.
    public fun mine_entries<BidAssetType, EntryType>(mempool: &mut Mempool<BidAssetType, EntryType>, miner: address, ctx: &mut TxContext): CB<EntryType> {
        // Validate time now >= last block time + block delay
        let now = tx_context::epoch(ctx);
        assert!(now >= mempool.last_block_timestamp + mempool.block_time, 1000);

        // Withdraw miner_fee_rate / 2**16 to the miner
        let miner_fee = coin::value(&mempool.current_block_bids) * mempool.miner_fee_rate / (1 << 16);
        coin::split_and_transfer(&mut mempool.current_block_bids, miner_fee, miner, ctx);

        // Send the rest to the mempool admin
        coin::join(&mut mempool.mempool_fees, coin::split(&mut mempool.current_block_bids, coin::value(&mempool.current_block_bids), ctx));

        // Get last block
        let last_block = Vector::pop_back(&mut mempool.blocks);

        // Create next block
        Vector::push_back(&mut mempool.blocks, CritBit::empty<EntryType>());
        *&mut mempool.last_block_timestamp = now;

        // Return entries of last block
        last_block
    }
}