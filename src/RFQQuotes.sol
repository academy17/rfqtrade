// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./RFQTrade.sol";


contract RFQQuotes is Initializable {

        event expirateBContractEvent(
        uint256 indexed bContractId
        );

    event openQuoteEvent(
        address indexed target,
        uint256 indexed bContractId, 
        bool isLong, 
        uint256 bOracleId, 
        uint256 price, 
        uint256 qty, 
        uint256 interestRate, 
        bool isAPayingAPR
        ); 
    event acceptQuoteEvent( 
        address indexed target, 
        uint256 indexed bContractId,  
        uint256 price);

    event acceptCloseQuoteEvent(
        address indexed target, 
        uint256 indexed bCloseQuoteId, 
        uint256 index, 
        uint256 amount 
        );

    event partialAcceptQuoteEvent(
        address indexed target, 
        uint256 indexed bContractId, 
        uint256 fillAmount
        );

    event cancelOpenCloseQuoteContractIdEvent(
        uint256 indexed bContractId
        );


    RFQTrade public rfq;
    function initialize(address _rfq_address) public initializer {
        rfq = RFQTrade(_rfq_address);
    }



    function openQuote( 
        bool isLong,
        uint256 bOracleId,
        uint256 price,
        uint256 qty,
        uint256 interestRate, 
        bool isAPayingAPR, 
        address frontEndAffiliate, 
        address frontEndAffiliateAffiliate
    ) public {
        require(rfq.getOpenPositionNumber(msg.sender) < rfq.MAX_OPEN_POSITIONS(), "too many positions" ); 
        require(qty * price > rfq.MIN_NOTIONAL(), "must be higher than minimum notional");
        bOracle memory oracle = rfq.getBOracle(bOracleId);
        rfq.setbContractVariablesQuote(
            msg.sender,
            rfq.getBContractLength(), 
            bOracleId, 
            price, qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate);

        if(isLong)  {
            require(((oracle.initialMarginA + oracle.defaultFundA) * qty * price / 1e18) < rfq.getBalance(msg.sender), "Balance Error");//CHECK MATH
            uint256 oldBalance = rfq.getBalance(msg.sender);
            uint256 updatedBalance = oldBalance - ((oracle.initialMarginA + oracle.defaultFundA) * qty * price / 1e18);
            rfq.setBalance(msg.sender, updatedBalance);
            rfq.setBContractParty(msg.sender, rfq.getBContractLength(), true);
        }
        else  {
            require(((oracle.initialMarginB + oracle.defaultFundB) * qty * price / 1e18) < rfq.getBalance(msg.sender), "Balance Error");//CHECK MATH
            uint256 oldBalance = rfq.getBalance(msg.sender);
            uint256 updatedBalance = oldBalance - ((oracle.initialMarginB + oracle.defaultFundB) * qty * price / 1e18);
            rfq.setBalance(msg.sender, updatedBalance);
            rfq.setBContractParty(msg.sender, rfq.getBContractLength(), false);
        }
        
        emit openQuoteEvent(msg.sender, rfq.getBContractLength(), isLong, bOracleId, price, qty, interestRate, isAPayingAPR);
        rfq.incrementbContractLength();
        rfq.incrementOpenPositionNumber(msg.sender);
        
    }

    function acceptQuote(
        uint256 _bContractId, 
        uint256 _acceptPrice, 
        address backendAffiliate
    ) public { 
        require(rfq.getOpenPositionNumber(msg.sender) < rfq.MAX_OPEN_POSITIONS(), "too many positions" ); //decrement
        bContract memory _bContract = rfq.getBContractMemory(_bContractId);
        bOracle memory oracle = rfq.getBOracle(rfq.getBContractMemory(_bContractId).oracleId);
        if(_bContract.openTime == block.timestamp && _bContract.state == _State.Open) {
            if(_bContract.initiator == _bContract.partyA && _acceptPrice < _bContract.price) { 
                require(rfq.getBalance(msg.sender) > (( oracle.initialMarginB + oracle.defaultFundB) * _bContract.price * _bContract.qty / 1e18), "BALANCE ERROR");
                uint256 oldPartyBRefund = rfq.getBalance(_bContract.partyB);
                oldPartyBRefund += ((oracle.initialMarginB + oracle.defaultFundB) * _bContract.price * _bContract.qty) / 1e18;
                rfq.setBalance(_bContract.partyB, oldPartyBRefund);
                rfq.setBContractParty(msg.sender, _bContractId, false);
                uint256 partyBNewBalance = rfq.getBalance(msg.sender);
                partyBNewBalance -= ((oracle.initialMarginB + oracle.defaultFundB) * _acceptPrice * _bContract.qty) / 1e18;
                rfq.setBalance(msg.sender, partyBNewBalance);
                uint256 partyABetterQuoteBalance = rfq.getBalance(_bContract.partyA);
                partyABetterQuoteBalance +=  (((oracle.initialMarginA + oracle.defaultFundA)) * (_bContract.price - _acceptPrice ) * _bContract.qty / 1e18);
                rfq.setBalance(_bContract.partyA, partyABetterQuoteBalance);
                rfq.setBContractPrice(_bContractId, _acceptPrice);
                }
            else if(_bContract.initiator == _bContract.partyB && _acceptPrice > _bContract.price) { 
                require(rfq.getBalance(msg.sender) > (( oracle.initialMarginA + oracle.defaultFundA) *_bContract.price * _bContract.qty / 1e18), "BALANCE TOO LOW");
                uint256 oldPartyARefund = rfq.getBalance(msg.sender);
                oldPartyARefund += (oracle.initialMarginA + oracle.defaultFundA) *_bContract.price * _bContract.qty / 1e18; //issue, when we refund, we refund the newly accepted _price, need to find some way of storing oldPride.
                rfq.setBalance(_bContract.partyA, oldPartyARefund);
                rfq.setBContractParty(msg.sender, _bContractId, true);
                uint256 partyANewBalance = rfq.getBalance(msg.sender);
                partyANewBalance -= ( oracle.initialMarginA + oracle.defaultFundA) * _acceptPrice * _bContract.qty / 1e18;
                rfq.setBalance(msg.sender, partyANewBalance);
                uint256 partyBBetterQuoteBalance = rfq.getBalance(_bContract.partyB);
                partyBBetterQuoteBalance += ((oracle.initialMarginB + oracle.defaultFundB)) * (_acceptPrice - _bContract.price ) * _bContract.qty / 1e18;
                rfq.setBalance(_bContract.partyB, partyBBetterQuoteBalance);
                rfq.setBContractPrice(_bContractId, _acceptPrice);
                }
            //emit acceptQuoteEvent(msg.sender, pairContractId, _acceptPrice);
        } else {
                require(_bContract.state == _State.Quote);
                if (_bContract.initiator == _bContract.partyA){
                    rfq.setBContractParty(msg.sender, _bContractId, false);
                    if(_acceptPrice < _bContract.price) {
                        require(rfq.getBalance(msg.sender) > (( oracle.initialMarginB + oracle.defaultFundB) *_acceptPrice * _bContract.qty / 1e18));
                        require(rfq.getBalance(msg.sender) > (((_bContract.price - _acceptPrice ) * _bContract.qty))) ; //check we have more than enough to settle instantly
                        uint256 partyBNewBalance = rfq.getBalance(msg.sender);
                        partyBNewBalance -= (oracle.initialMarginB + oracle.defaultFundB) *_acceptPrice * _bContract.qty / 1e18;
                        rfq.setBalance(msg.sender, partyBNewBalance);
                        uint256 partyABetterQuoteBalance = rfq.getBalance(_bContract.partyA);
                        partyABetterQuoteBalance += ((oracle.initialMarginA + oracle.defaultFundA)) * (_bContract.price - _acceptPrice ) * _bContract.qty / 1e18; //logic correction, its possible to get 2x profit if user settle instantly
                        rfq.setBalance(_bContract.partyA, partyABetterQuoteBalance);
                        rfq.setBContractPrice(_bContractId, _acceptPrice);
                    } else {
                        require(rfq.getBalance(msg.sender) > (( oracle.initialMarginB + oracle.defaultFundB) *_bContract.price * _bContract.qty / 1e18)); 
                        uint256 partyBNewBalance = rfq.getBalance(msg.sender);
                        partyBNewBalance -= (oracle.initialMarginB + oracle.defaultFundB) *_acceptPrice * _bContract.qty / 1e18;
                        rfq.setBalance(msg.sender, partyBNewBalance);
                    }
                }
                if (_bContract.initiator == _bContract.partyB){
                    rfq.setBContractParty(msg.sender, _bContractId, true);
                    if(_acceptPrice > _bContract.price) {
                        require(rfq.getBalance(_bContract.partyB) > ((oracle.initialMarginB + oracle.defaultFundB)) * (_acceptPrice - _bContract.price ) * _bContract.qty / 1e18); //ensure p[b] jas enough collateral, offset by instant settlement
                        require(rfq.getBalance(msg.sender) > (((_acceptPrice - _bContract.price) * _bContract.qty))) ; //check we have more than enough to settle instantly
                        require(rfq.getBalance(msg.sender) > (( oracle.initialMarginA + oracle.defaultFundA) *_acceptPrice * _bContract.qty /1e18)); 
                        uint256 partyANewBalance = rfq.getBalance(msg.sender);
                        partyANewBalance -= ( oracle.initialMarginA + oracle.defaultFundA) *_acceptPrice * _bContract.qty / 1e18;
                        rfq.setBalance(msg.sender, partyANewBalance);
                        uint256 partyBBetterQuoteBalance = rfq.getBalance(_bContract.partyB);
                        partyBBetterQuoteBalance -= ((oracle.initialMarginB + oracle.defaultFundB)) * (_acceptPrice - _bContract.price ) * _bContract.qty / 1e18; //takes a little more from partyB
                        rfq.setBalance(_bContract.partyB, partyBBetterQuoteBalance);
                        rfq.setBContractPrice(_bContractId, _acceptPrice);
                    }
                    else {
                        require(rfq.getBalance(msg.sender) > ( ( oracle.initialMarginA + oracle.defaultFundA) *_bContract.price * _bContract.qty / 1e18)); 
                        uint256 partyANewBalance = rfq.getBalance(msg.sender);
                        partyANewBalance -= ( oracle.initialMarginA + oracle.defaultFundA) * _bContract.price * _bContract.qty / 1e18;
                        rfq.setBalance(msg.sender, partyANewBalance);
                    }
                }
                rfq.setBContractAffiliate(_bContractId, backendAffiliate);
                rfq.setBContractState(_bContractId, _State.Open);
                rfq.setBContractOpenTime(_bContractId, block.timestamp);
                rfq.incrementOpenPositionNumber(msg.sender);
                _bContract.backEndAffiliate = backendAffiliate;
                //emit acceptQuoteEvent(msg.sender, _bContractId, pairContractId, _acceptPrice);
        }
    }

    function partialAcceptQuote(
        uint256 _bContractId, 
        uint256 fillAmount, 
        address backEndAffiliate
        ) public {
        bContract memory _bContract = rfq.getBContractMemory(_bContractId);
        bOracle memory _bOracle = rfq.getBOracle(rfq.getBCloseQuotesLength());
        require(_bContract.state == _State.Quote);
        if (_bContract.initiator == _bContract.partyA) {
            require(rfq.getBalance(msg.sender) > ((_bOracle.initialMarginB + _bOracle.defaultFundB) *_bContract.price * fillAmount / 1e18), "invalid bal");
            uint256 oldBalanceB = rfq.getBalance(msg.sender);
            oldBalanceB -= (_bOracle.initialMarginB + _bOracle.defaultFundB) *_bContract.price * fillAmount / 1e18;
            rfq.setBContractParty(msg.sender, _bContractId, false);
            rfq.setBalance(msg.sender, oldBalanceB);
            rfq.incrementbContractLength();
            rfq.setBContractParty(_bContract.partyA, rfq.getBContractLength(), true);
            uint256 newBalanceA = rfq.getBalance(_bContract.partyA);
            newBalanceA += (_bOracle.initialMarginA + _bOracle.defaultFundA) * _bContract.price * fillAmount / 1e18;
            rfq.setBalance(_bContract.partyA, newBalanceA);
            rfq.setbContractVariablesQuote(
            _bContract.partyA,
            rfq.getBContractLength(), 
            _bContract.oracleId, 
            _bContract.price, 
            _bContract.qty - fillAmount, 
            _bContract.interestRate,
            _bContract.isAPayingAPR,
            _bContract.frontEndAffiliate,
            _bContract.frontEndAffiliateAffiliate);
            rfq.setBContractAffiliate(_bContractId, backEndAffiliate);
            rfq.setBContractState(_bContractId, _State.Open);
            rfq.setBContractState(rfq.getBContractLength(), _State.Quote);
        }
        if (_bContract.initiator == _bContract.partyB){
            require(rfq.getBalance(msg.sender) > (( _bOracle.initialMarginA + _bOracle.defaultFundA) *_bContract.price * fillAmount / 1e18), "invalid bal"); 
            uint256 oldBalanceA = rfq.getBalance(msg.sender);
            oldBalanceA -= (_bOracle.initialMarginA + _bOracle.defaultFundA) *_bContract.price * fillAmount / 1e18;
            rfq.setBContractParty(msg.sender, _bContractId, true);
            rfq.setBalance(msg.sender, oldBalanceA);
            rfq.incrementbContractLength();
            rfq.setBContractParty(_bContract.partyB, rfq.getBContractLength(), false);
            uint256 newBalanceB = rfq.getBalance(_bContract.partyB);
            newBalanceB += (_bOracle.initialMarginB + _bOracle.defaultFundB) * _bContract.price * fillAmount / 1e18;
            rfq.setBalance(_bContract.partyB, newBalanceB);
            rfq.setbContractVariablesQuote(
            _bContract.partyB,
            rfq.getBContractLength(), 
            _bContract.oracleId, 
            _bContract.price, 
            _bContract.qty - fillAmount, 
            _bContract.interestRate,
            _bContract.isAPayingAPR,
            _bContract.frontEndAffiliate,
            _bContract.frontEndAffiliateAffiliate);
            rfq.setBContractAffiliate(_bContractId, backEndAffiliate);
            rfq.setBContractState(_bContractId, _State.Open);
            rfq.setBContractState(rfq.getBContractLength(), _State.Quote);
        }
        
        //_bContract.qty = fillAmount;
        //bCloseQuotesLength++; //unsafe?
        //rfq.incrementOpenPositionNumber(msg.sender); //we don't need to increment openPositionNumber because one was closed
        //emit partialAcceptQuoteEvent(msg.sender, _bContractId, fillAmount);
            
        // Finish 
        }

        function cancelOpenQuote(uint256 _bContractId) public {
        bContract memory _bContract = rfq.getBContractMemory(_bContractId);
        bOracle memory _bOracle = rfq.getBOracle(_bContract.oracleId);
        require( _bContract.state == _State.Open);
        if(msg.sender == _bContract.partyA ){
            uint256 oldBalanceA = rfq.getBalance(msg.sender);
            oldBalanceA += (_bOracle.initialMarginA + _bOracle.defaultFundA) * _bContract.qty * _bContract.price / 1e18;
            rfq.setBalance(_bContract.partyA, oldBalanceA);
            rfq.decrementOpenPositionNumber(msg.sender);
            rfq.setBContractState(_bContractId, _State.Closed);
        }
        else{
        require( msg.sender == _bContract.partyB );
            uint256 oldBalanceB = rfq.getBalance(msg.sender);
            oldBalanceB += (_bOracle.initialMarginB + _bOracle.defaultFundB) * _bContract.qty * _bContract.price / 1e18;
            rfq.setBalance(_bContract.partyB, oldBalanceB);
            rfq.decrementOpenPositionNumber(msg.sender);
            rfq.setBContractState(_bContractId, _State.Closed);
        }
        //emit cancelOpenQuoteEvent(bContractId );
    }

    function openCloseQuote(
        uint256[] memory bContractIds,
        uint256[] memory price, 
        uint256[] memory qty, 
        uint256[] memory limitOrStop, 
        uint256 expiration,
        address initiator
    ) public {
        require(bContractIds.length == price.length, "Arrays must be of the same length");
        require(bContractIds.length == qty.length, "Arrays must be of the same length");
        require(bContractIds.length == limitOrStop.length, "Arrays must be of the same length");
        for(uint i = 0; i < bContractIds.length; i++) {
        bContract memory _bContract = rfq.getBContractMemory(bContractIds[i]);
        require(msg.sender == _bContract.partyA || msg.sender == _bContract.partyB,
            "Sender must be partyA or partyB of the bContract"
        );
        }
        rfq.setBContractCloseQuote(bContractIds, price, qty, limitOrStop, msg.sender, expiration);
    }


    function cancelOpenCloseQuoteBatch(uint256 bCloseQuoteId) public {
        bCloseQuote memory quote = rfq.getBCloseQuote(bCloseQuoteId);
        require(msg.sender == quote.initiator);
        require(quote.state == _State.Quote, "Quote must be in Quote state");
        for (uint256 i = 0; i < quote.bContractIds.length; i++) { 
            rfq.setBContractState(quote.bContractIds[i], _State.Canceled);
            emit cancelOpenCloseQuoteContractIdEvent(quote.bContractIds[i]);
        }
    }

    function cancelOpenCloseQuoteOrder(uint256 _bContractId) public { 
        bCloseQuote memory quote = rfq.getBCloseQuote(_bContractId);
        require(msg.sender == quote.initiator);
        require(quote.state != _State.Canceled, "Quote already canceled");
        quote.state = _State.Canceled;
        //emit cancelOpenCloseQuoteContractIdEvent(_bContractId);
    }



}