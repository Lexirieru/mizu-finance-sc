// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./MizuMarketplace.sol";

contract DLT is IDLT, Ownable {
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        private _balances;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(address => uint256))))
        private _allowances;

    constructor() Ownable(msg.sender) {}

    function mint(
        address to,
        uint256 mainId,
        uint256 subId,
        uint256 amount
    ) external {
        require(
            msg.sender == owner() || isApprovedForAll(owner(), msg.sender),
            "Not authorized"
        );
        _balances[to][mainId][subId] += amount;
        emit Transfer(address(0), to, mainId, subId, amount);
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) external override {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(
        address sender,
        address recipient,
        uint256 mainId,
        uint256 subId,
        uint256 amount,
        bytes calldata
    ) external override returns (bool) {
        require(
            sender == msg.sender ||
                isApprovedForAll(sender, msg.sender) ||
                allowance(sender, msg.sender, mainId, subId) >= amount,
            "Not approved"
        );
        require(
            _balances[sender][mainId][subId] >= amount,
            "Insufficient balance"
        );

        _balances[sender][mainId][subId] -= amount;
        _balances[recipient][mainId][subId] += amount;

        if (allowance(sender, msg.sender, mainId, subId) >= amount) {
            _allowances[sender][mainId][subId][msg.sender] -= amount;
        }

        emit Transfer(sender, recipient, mainId, subId, amount);
        return true;
    }

    function approve(
        address operator,
        uint256 mainId,
        uint256 subId,
        uint256 amount
    ) external override returns (bool) {
        _allowances[msg.sender][mainId][subId][operator] = amount;
        emit Approval(msg.sender, operator, mainId, subId, amount);
        return true;
    }

    function subBalanceOf(
        address account,
        uint256 mainId,
        uint256 subId
    ) external view override returns (uint256) {
        return _balances[account][mainId][subId];
    }

    function balanceOfBatch(
        address[] calldata accounts,
        uint256[] calldata mainIds,
        uint256[] calldata subIds
    ) external view override returns (uint256[] memory) {
        require(
            accounts.length == mainIds.length &&
                mainIds.length == subIds.length,
            "Length mismatch"
        );
        uint256[] memory balances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            balances[i] = _balances[accounts[i]][mainIds[i]][subIds[i]];
        }
        return balances;
    }

    function allowance(
        address owner,
        address operator,
        uint256 mainId,
        uint256 subId
    ) public view override returns (uint256) {
        return _allowances[owner][mainId][subId][operator];
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }
}
