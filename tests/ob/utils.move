#[test_only]
module nft_protocol::test_ob_utils {
    use nft_protocol::nft;
    use nft_protocol::collection::{Self, Collection};
    use nft_protocol::ob::{Self, Orderbook};
    use nft_protocol::safe::{Self, Safe};
    use nft_protocol::transfer_whitelist::{Self, Whitelist};
    use nft_protocol::unprotected_safe::{OwnerCap};
    use sui::sui::SUI;
    use sui::coin;
    use std::vector;
    use sui::object::{Self, ID};
    use sui::test_scenario::{Self, Scenario, ctx};
    use sui::transfer::{transfer, share_object};

    const BUYER: address = @0xA1C06;
    const CREATOR: address = @0xA1C05;
    const SELLER: address = @0xA1C04;

    const OFFER_SUI: u64 = 100;

    struct Foo has drop {} // collection
    struct Witness has drop {} // collection witness, must be named witness
    struct WhitelistWitness has drop {}

    public fun create_collection_and_whitelist(scenario: &mut Scenario) {
        let (cap, col) = collection::dummy_collection<Foo>(&Foo {}, CREATOR, scenario);
        share_object(col);
        test_scenario::next_tx(scenario, CREATOR);

        let col_control_cap = transfer_whitelist::create_collection_cap<Foo, Witness>(
            &Witness {}, ctx(scenario),
        );

        let col: Collection<Foo> = test_scenario::take_shared(scenario);
        nft_protocol::example_free_for_all::init_(ctx(scenario));
        test_scenario::next_tx(scenario, CREATOR);

        let wl: Whitelist = test_scenario::take_shared(scenario);
        nft_protocol::example_free_for_all::insert_collection(
            &col_control_cap,
            &mut wl,
        );

        transfer(cap, CREATOR);
        transfer(col_control_cap, CREATOR);
        test_scenario::return_shared(col);
        test_scenario::return_shared(wl);
    }

    public fun create_ob(scenario: &mut Scenario) {
        let ob = ob::create_protected<Witness, Foo, SUI>(
            Witness {}, ctx(scenario)
        );
        ob::share(ob);

        test_scenario::next_tx(scenario, CREATOR);
    }

    public fun create_seller_safe_and_make_an_offer_for_nft_id(
        scenario: &mut Scenario,
    ): ID {
        let seller_owner_cap = safe::create_safe(true, ctx(scenario));
        test_scenario::next_tx(scenario, SELLER);

        let seller_safe: Safe = test_scenario::take_shared_by_id(
            scenario,
            safe::owner_cap_safe(&seller_owner_cap),
        );

        let nft = nft::new<Foo>(ctx(scenario));
        let nft_id = object::id(&nft);
        safe::deposit_nft<Foo>(
            nft,
            &mut seller_safe,
            ctx(scenario),
        );
        let transfer_cap = safe::create_exclusive_transfer_cap(
            nft_id,
            &seller_owner_cap,
            &mut seller_safe,
            ctx(scenario)
        );

        let ob: Orderbook<Foo, SUI> = test_scenario::take_shared(scenario);
        ob::create_ask(
            &mut ob,
            OFFER_SUI,
            transfer_cap,
            &mut seller_safe,
            ctx(scenario),
        );

        test_scenario::return_shared(ob);
        test_scenario::return_shared(seller_safe);
        transfer(seller_owner_cap, SELLER);

        test_scenario::next_tx(scenario, SELLER);

        nft_id
    }

    public fun buy_nft(scenario: &mut Scenario, nft_id: ID) {
        let buyer_owner_cap = safe::create_safe(true, ctx(scenario));

        test_scenario::next_tx(scenario, BUYER);

        let wallet = coin::mint_for_testing(OFFER_SUI, ctx(scenario));

        test_scenario::next_tx(scenario, BUYER);

        let buyer_safe: Safe = test_scenario::take_shared_by_id(
            scenario,
            safe::owner_cap_safe(&buyer_owner_cap),
        );
        let ob: Orderbook<Foo, SUI> = test_scenario::take_shared(scenario);

        ob::create_bid(
            &mut ob,
            &mut buyer_safe,
            OFFER_SUI,
            &mut wallet,
            ctx(scenario),
        );
        test_scenario::return_shared(ob);
        coin::destroy_zero(wallet);

        test_scenario::next_tx(scenario, BUYER);

        let seller_safe_id = user_safe_id(scenario, SELLER);
        let seller_safe: Safe = test_scenario::take_shared_by_id(
            scenario,
            seller_safe_id,
        );
        let ti: ob::TradeIntermediate<Foo, SUI> =
            test_scenario::take_shared(scenario);
        let wl: Whitelist = test_scenario::take_shared(scenario);

        assert!(!safe::has_nft<Foo>(nft_id, &buyer_safe), 0);
        assert!(safe::has_nft<Foo>(nft_id, &seller_safe), 0);

        ob::finish_trade(
            &mut ti,
            &mut seller_safe,
            &mut buyer_safe,
            &wl,
            ctx(scenario),
        );

        assert!(safe::has_nft<Foo>(nft_id, &buyer_safe), 0);
        assert!(!safe::has_nft<Foo>(nft_id, &seller_safe), 0);

        test_scenario::return_shared(ti);
        test_scenario::return_shared(buyer_safe);
        test_scenario::return_shared(seller_safe);
        test_scenario::return_shared(wl);

        transfer(buyer_owner_cap, BUYER);
    }

    public fun user_safe_id(scenario: &Scenario, user: address): ID {
        let owner_cap_id = vector::pop_back(
            &mut test_scenario::ids_for_address<OwnerCap>(user)
        );
        let owner_cap: OwnerCap =
            test_scenario::take_from_address_by_id(scenario, user, owner_cap_id);

        let safe_id = safe::owner_cap_safe(&owner_cap);

        test_scenario::return_to_address(user, owner_cap);

        safe_id
    }

    public fun cancel_bid(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, BUYER);

        let wallet = coin::mint_for_testing(OFFER_SUI, ctx(scenario));

        test_scenario::next_tx(scenario, BUYER);

        let ob: Orderbook<Foo, SUI> = test_scenario::take_shared(scenario);

        ob::cancel_bid(
            &mut ob,
            OFFER_SUI,
            &mut wallet,
            ctx(scenario),
        );
        test_scenario::return_shared(ob);
        test_scenario::return_to_sender(scenario ,wallet);
    }
}
