pragma solidity ^0.4.0;

import "fundManager.sol";

//----------------------------------------------------------------
// WARNING: this contract conteains testing code that 
// allows for the creation of balances out of nothing for testing
// do not use this code for anything other than testing until this code is removed
// to remove this code delete "TESTINGEXPLOIT_" from ex8 
//----------------------------------------------------------------

contract TESTINGEXPLOIT_FundManager is FundManager
{
    function fakeDeposit(address token, uint value) {
       tokenBalance[token][msg.sender] += value; // generate balance for testing 
    }

}

// ex8, 8th iteration if /u/jonnylatte's exchange with order matching
// this code is still in development, does not cointain full functionality
// and most likely cointains vulnerabilities and other unintended behavior


contract ex8 is TESTINGEXPLOIT_FundManager {
    
    mapping(uint => uint) next; // single linked lists 
    
    // BOOK contains information about a currency pair 
    
    struct BOOK {
        address asset;    // token to be considered the asset
        address currency; // token to be considered the currency
        uint units;       // multiplier for asset / smallest asset trade
        uint bid;         // index of the top buy order
        uint ask;         // index to the top sell order   
    }
    
    // ORDER contains information about a trade.
    // order balances are stored in the index of the
    
    struct ORDER {
        address owner;
        uint price;
    }  
    
    uint public bookCount;
    uint public nextOrder = 1;
    
    mapping(uint => BOOK) books;
    mapping(uint => ORDER) orders;
    
    mapping(bytes32 => bool) bookLog;

    event NewBook(uint bookid, address indexed asset, address indexed currency, uint units);
    
    // list operation: count nodes after and including top
    function countNodes(uint top) internal constant returns (uint count) {
        while(top != 0) {
            count++;
            top = next[top];
        }
    }
    
    //list operation: Get index before "node" in list starting at "top"
    function getPrevious(uint top, uint node) internal constant returns (uint) {
        uint previousid;
        while(top != 0) {
            previousid = top;
            top = next[top];
        }
        return previousid;
    }
    
    // get previous ask index by price
    function getPrevAsk(uint bookid, uint price) constant returns (uint) {
        if(books[bookid].ask == 0) return 0;
        uint prev = 0;
        var i = books[bookid].ask;
        while(i != 0 && price >= orders[i].price) {
            (prev,i) = (i,next[i]);
        }
        return prev; 
    }
    
    // get previous bid index by price
    function getPrevBid(uint bookid, uint price) constant returns (uint) {
        if(books[bookid].bid == 0) return 0;
        uint prev = 0;
        var i = books[bookid].bid;
        while(i != 0 && price <= orders[i].price) {
            (prev,i) = (i,next[i]);
        }
        return prev; 
    }
    
    // returns information about an orderbook
    function getBook(uint id) constant returns (
            address asset,
            address currency,
            uint units,
            uint bidCount,
            uint askCount
        ) {
        var book = books[id];
        asset    = book.asset;
        currency = book.currency;
        units    = book.units;
        bidCount = countNodes(book.bid);
        askCount = countNodes(book.ask);
    } 
    
    // create a trading pair / units combination
    function makeBook(address asset, address currency, uint units) {
        if(units == 0) throw;
        if(asset == currency) throw;
        var bookHash = sha3(asset,currency,units);
        if(!bookLog[bookHash]) {
            BOOK memory b;
            b.asset = asset;
            b.currency = currency;
            b.units = units;
            books[bookCount] = b;
            NewBook(bookCount, asset,  currency,  units);
            bookCount++;
        }
    }
 
    // get information about a sell order
    function getAsk(uint bookid,uint pos) constant 
        returns (
            uint previousid, 
            uint price,
            uint assetBalance,
            address owner,
            uint id,
            uint position)
    {
        id = books[bookid].ask;
        while(id != 0 && pos != 0) { pos--; previousid = id; id = next[id]; }
        price = orders[id].price;
        assetBalance = balanceOf(books[bookid].asset,(address)(id));
        owner = orders[id].owner;
        position = pos;
    }
    
    // get information about a buy order
    function getBid(uint bookid,uint pos) constant 
        returns (
            uint previousid, 
            uint price,
            uint currencyBalance,
            address owner,
            uint id,
            uint position)
    {
        id = books[bookid].bid;
        while(id != 0 && pos != 0) { pos--; previousid = id; id = next[id]; }
        price = orders[id].price;
        currencyBalance = balanceOf(books[bookid].currency,(address)(id));
        owner = orders[id].owner;
        position = pos;
    }
    
    // remove an order from a book and refund its balance
    function cancelOrder(uint bookid, uint prev, uint id, bool ask) {
        // get orderbook
        var book = books[bookid]; 
        if(book.units == 0) throw;  
        
        // test previous actually links to _id
        if(prev == 0) if(ask && book.ask != id || !ask && book.bid != id) throw;  
        else if(next[prev] != id) throw;
        
        //test sender owns order
        if(orders[id].owner != msg.sender) throw;
        
        // remove order from book
        if(prev == 0) {
            if(ask) books[bookid].ask = next[id];
            else books[bookid].bid = next[id];
        }
        else next[prev] = next[id];
        
        // delete order
        delete next[id];
        delete orders[id];
        
        //refund order funds
        if(ask) appTransfer(book.asset,(address)(id),msg.sender, balanceOf(book.asset,(address)(id)));
        else appTransfer(book.currency,(address)(id),msg.sender, balanceOf(book.currency,(address)(id)));
    }
    
    // sell asset potentially placing an ask order if speified and not matched
    
    function sell(uint bookid, uint lotSize, uint price, uint prev, bool make) {
        var book = books[bookid]; 
        if(book.units == 0) throw;
        
        appTransfer(book.asset,msg.sender,(address)(nextOrder),lotSize * book.units);
        
        while(book.bid != 0) {
            var bid = orders[book.bid];
            if(bid.price < price) break;
            
            uint canFill = balanceOf(book.asset,(address)(nextOrder)) / book.units;
            uint wantFill = balanceOf(book.currency,(address)(book.bid)) / bid.price;

            if(canFill >= wantFill) // bid filled completely
            { 
                appTransfer(book.currency,(address)(book.bid),msg.sender,balanceOf(book.currency,(address)(book.bid)));
                appTransfer(book.asset,(address)(nextOrder),bid.owner,wantFill * book.units);
                uint tmp = book.bid; // pop bid
                book.bid = next[book.bid];
                delete orders[tmp];
                delete next[tmp];
            }
            else // partial fill
            {
                appTransfer(book.currency,(address)(book.bid),msg.sender,canFill * bid.price);
                appTransfer(book.asset,(address)(nextOrder),bid.owner,canFill * book.units);
                return;
            }
        }
        
        if(balanceOf(book.asset, (address)(nextOrder)) == 0) return;

        if(!make) // no placing of order refund change and exit
        { 
            appTransfer(book.asset,(address)(nextOrder),msg.sender, balanceOf(book.asset,(address)(nextOrder)));
            return;
        }
        
        // no matching bid place order on book 
        ORDER memory o; 
        o.owner = msg.sender;
        o.price = price;
        orders[nextOrder] = o;
       
        if(prev == 0) // at the top of book 
        {   
            if(book.ask != 0 && price >= orders[book.ask].price) throw; // price check
            next[nextOrder] = book.ask; // link order to top ask
            book.ask = nextOrder; // set top ask to order
        }
        else // after some other order
        { 
            if( (price < orders[prev].price) ||  (next[prev] != 0 && price >= orders[next[prev]].price)) throw; // price check
            next[nextOrder] = next[prev];    // link order to previous next
            next[prev] = nextOrder; // link previous to order
        }
        nextOrder++; 
    }
    
    // buy asset potentially placing an bid order if speified and not matched
    
    function buy(uint bookid, uint lotSize, uint price, uint prev, bool make) {
        var book = books[bookid]; 
        if(book.units == 0) throw;
        
        appTransfer(book.currency,msg.sender,(address)(nextOrder),lotSize*price);
        
        while(book.ask != 0) {
            var ask = orders[book.ask];
            if(ask.price > price) break;
            
            uint askBalance = balanceOf(book.asset,(address)(book.ask));
            uint wantFill =  askBalance / book.units;
            uint canFill = balanceOf(book.currency,(address)(nextOrder)) / ask.price;
            
            if(canFill >= wantFill) // fill ask completely
            {
                appTransfer(book.asset,(address)(book.ask),msg.sender,askBalance);
                appTransfer(book.currency,(address)(nextOrder),ask.owner,wantFill*ask.price);
                
                uint tmp =  book.ask; // pop ask
                book.ask = next[book.ask];
                delete next[tmp];
                delete orders[tmp];
            }
            else // partial fill
            {
                appTransfer(book.asset,(address)(book.ask),msg.sender,canFill*book.units);
                appTransfer(book.currency,(address)(nextOrder),ask.owner,canFill*ask.price);
                
                return;
            }
        }
        
        if(balanceOf(book.currency, (address)(nextOrder)) == 0) return;
        
        if(!make) // no placing of order refund change and exit
        { 
            appTransfer(book.currency,(address)(nextOrder),msg.sender, balanceOf(book.currency,(address)(nextOrder)));
            return;
        }
        
        // no matching bid place ask 
        ORDER memory o; 
        o.owner = msg.sender;
        o.price = price;
        orders[nextOrder] = o;
    
        if(prev == 0) // at the top of book 
        {   
            if(book.bid != 0 && price <= orders[book.bid].price) throw;  //price check
            next[nextOrder] = book.bid; // push bid;
            book.bid = nextOrder;
        }
        else // after some other order
        { 
            if((price > orders[prev].price)  || (next[prev] != 0 && price <= orders[next[prev]].price)) throw; // price check
            next[nextOrder] = next[prev]; 
            next[prev] = nextOrder;
        }
        nextOrder++;
    }
    
    // find position in book to sell and call sell
    // this calculation should be done off chain to avoid walking onchain
    // just call the constant function getPrevAsk to get prev off chain then 
    // call sell. Might be useful to ensure order placement in busy market though
    // using this to place an order deep in the orderbook may resut in out of gas problems
    
    function ultraSell(uint bookid, uint lotSize, uint price, bool make) {
        sell( bookid,  lotSize,  price, getPrevAsk( bookid,  price) ,  make);
    }
    
    function ultraBuy(uint bookid, uint lotSize, uint price, bool make) {
        buy( bookid,  lotSize,  price, getPrevBid( bookid,  price) ,  make);
    }
}