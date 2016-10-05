pragma solidity ^0.4.0;

import "erc20.sol";

// Holds tokens for multiple users allowing for deposits and withdrawals
// internal and external transfers

contract FundManager {
    mapping (address => uint256) public funds;
    mapping (address => mapping (address => uint256)) public tokenBalance;

    event Deposit(address indexed _from, address indexed _token, uint256 _value);
    event Withdraw(address indexed _to, address indexed _token, uint256 _value);
    event Transfer(address indexed _from, address indexed _to, address indexed _token, uint256 _value, bool isInternal);
    
    bool mutex;
    
    modifier preventRecursion() {
        if(mutex == false) {
            mutex = true;
            _;
            mutex = false;
        }
        else throw;
    }

    function deposit(address _from, uint256 _value, address _token) preventRecursion
    {
        if(!ERC20(_token).transferFrom(_from,this,_value)) throw;               // external call 1
        uint256 balance = ERC20(_token).balanceOf(this);                        // external call 2
        uint256 value = balance - funds[_token];
        tokenBalance[msg.sender][_token] += value;
        funds[_token] = balance;
        Deposit(msg.sender,_token, value);
    }
    
    function withdraw(address _token, uint256 _value) preventRecursion {
        transfer(_token, msg.sender, _value);
    }
    
    function balance(address _token) returns (uint256) {
        return tokenBalance[msg.sender][_token];
    } 
    
    function transfer(address _token, address _to, uint256 _value) preventRecursion {
        if(tokenBalance[msg.sender][_token] < _value) throw;
        funds[_token] -= _value;
        tokenBalance[msg.sender][_token] -= _value;
        if(!ERC20(_token).transfer(_to,_value)) throw;                          // external call 3
        var fund_balance = ERC20(_token).balanceOf(this);                       // external call 4
        if(funds[_token] < fund_balance) 
        {
            // if after transfer contract funds are lower than expected
            // try and remove shortfall from user account (assume it was a fee built into the token) otherwise throw
            uint256 fee = funds[_token] - fund_balance;
            if(fee > tokenBalance[msg.sender][_token]) throw;
            tokenBalance[msg.sender][_token] -= fee;
            funds[_token] = fund_balance;
        }
        Transfer(msg.sender,_to,_token,_value,false);
    }  
    
    function internalTransfer(address _token, address _to, uint256 _value) preventRecursion {
        appTransfer(msg.sender, _token, _to, _value);
    } 
    
    function appTransfer(address owner, address _token, address _to, uint256 _value) internal {
        if(tokenBalance[owner][_token] < _value) throw;
        tokenBalance[owner][_token] -= _value;
        tokenBalance[_to][_token] += _value;
        Transfer(msg.sender,_to,_token,_value,true);
    } 
}
