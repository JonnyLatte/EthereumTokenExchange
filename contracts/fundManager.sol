pragma solidity ^0.4.4;

import "github.com/JonnyLatte/MiscSolidity/erc20.sol";

// Holds tokens for multiple users allowing for deposits and withdrawals
// internal and external transfers

contract FundManager {
    mapping (address => uint256) public funds; // integrity check
    mapping (address => mapping (address => uint256)) tokenBalance;
    mapping (address => mapping (address => mapping (address => uint256))) approvals;

    event Deposit( address indexed _token, address indexed _from, address indexed _to  , uint256 _value);
    event Withdraw(address indexed _token, address indexed _from, address indexed _to  , uint256 _value);
    event Transfer(address indexed _token, address indexed _from, address indexed _to,  uint256 _value);
    event Approval(address indexed _token, address indexed owner, address indexed spender, uint value);

    function deposit(address _token,address _to, uint256 _value ) 
    {
        if(!ERC20(_token).transferFrom(msg.sender,this,_value)) throw;               // external call 1
        uint256 balance = ERC20(_token).balanceOf(this);                        // external call 2
        uint256 value = balance - funds[_token];
        tokenBalance[_token][ _to] += value;
        funds[_token] = balance;
        Deposit(_token,msg.sender,_to, value);
    }

    function withdraw(address _token, address _to, uint256 _value)  {
        if(tokenBalance[_token][msg.sender] < _value) throw;
        funds[_token] -= _value;
        tokenBalance[_token][msg.sender] -= _value;
        if(!ERC20(_token).transfer(_to,_value)) throw;                          // external call 3
        var fund_balance = ERC20(_token).balanceOf(this);                       // external call 4
        if(funds[_token] < fund_balance) 
        {
            // if after transfer contract funds are lower than expected
            // try and remove shortfall from user account (assume it was a fee built into the token) otherwise throw
            uint256 fee = funds[_token] - fund_balance;
            if(fee > tokenBalance[_token][msg.sender]) throw;
            tokenBalance[_token][msg.sender] -= fee;
            funds[_token] = fund_balance;
        }
        Withdraw(_token,msg.sender,_to , _value);
    }  
    
    function transfer(address token, address to, uint256 value)  {
        appTransfer(token, msg.sender,  to, value);
        Transfer(token, msg.sender, to, value);
    }
    
    function balanceOf(address token, address user) constant returns (uint) {
        return tokenBalance[token][user];
    }
    
    function approve(address token, address spender, uint value) returns (bool ok) {
        approvals[token][msg.sender][spender] = value;
        Approval(token, msg.sender, spender, value );
        return true;
    }
    
    function allowance(address token, address owner, address spender) constant returns (uint _allowance) {
        return approvals[token][owner][spender];
    }
    
    function transferFrom(address token, address from, address to, uint value) returns (bool ok) {
        // if you don't have enough balance, throw
        if( tokenBalance[token][from] < value ) {
            throw;
        }
        // if you don't have approval, throw
        if(approvals[token][from][msg.sender] < value ) throw;
        if(tokenBalance[token][to] + value < tokenBalance[token][to]) throw;
        // transfer and return true
        approvals[token][from][msg.sender] -= value;
        tokenBalance[token][from] -= value;
        tokenBalance[token][to] += value;
        Transfer(token, from, to, value);
        return true;
    }
    
    function appTransfer(address _token, address owner,  address _to, uint256 _value) internal returns (bool ok) {
        if(tokenBalance[_token][owner] < _value) throw;
        tokenBalance[_token][owner] -= _value;
        tokenBalance[_token][_to] += _value;
        Transfer(msg.sender,_to,_token,_value);
    } 
}
