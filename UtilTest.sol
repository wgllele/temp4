// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;


contract UtilTest{
    address private _owner;
    error OwnableInvalidOwner(address owner);
    error RefundETHFailed();

    constructor (address initialOwner) payable {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _owner = initialOwner;
    }
    function owner() public view returns (address) {
        return _owner;
    }
    receive() external payable {}
    fallback() external payable {}

    function sweepToken(
        address token,
        uint256 amount
    ) external payable {
        address recipient=_owner;
        assembly ("memory-safe") {
            let emptyPointer := mload(0x40)
            mstore(emptyPointer, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(emptyPointer, 0x04), recipient)
            mstore(add(emptyPointer, 0x24), amount)
            if iszero(call(gas(), token, 0, emptyPointer, 0x44, 0, 0)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }
   function refundETH() external payable {
        uint bal=address(this).balance;
        if (bal > 0){
            (bool success,) = payable(_owner).call{value: bal}(new bytes(0));
            if (!success) revert RefundETHFailed();
        }
    }
    /// @notice 按 CREATE 规则，从 `account` 的 `nonceBegin` 起连续推算 `num` 个合约地址。
    /// @param packed `abi.encodePacked(address account, uint24 nonceBegin, uint16 num)`，共 25 字节。
    /// @dev address = keccak256(rlp([account, nonce]))[12:]；RLP 写 scratch space，逻辑同 Solady LibRLP。
    function getContractFromAccountByNonce(
        bytes25 packed
    ) public pure returns (address[] memory accounts){
        uint num;
        assembly {
            num := and(shr(56, packed), 0xffff)
        }
        accounts = new address[](num);
        assembly {
            let account := shr(96, packed)
            let nonce := and(shr(72, packed), 0xffffff)
            let result := add(accounts, 0x20)
            let mask := 0xffffffffffffffffffffffffffffffffffffffff

            for { let i := 0 } lt(i, num) { i := add(i, 1) } {
                let deployed
                // nonce ∈ [0, 0x7f]：单字节（0 编码为 0x80）
                if iszero(gt(nonce, 0x7f)) {
                    mstore(0x00, account)
                    mstore8(0x0b, 0x94)
                    mstore8(0x0a, 0xd6)
                    mstore8(0x20, or(shl(7, iszero(nonce)), nonce))
                    deployed := and(keccak256(0x0a, 0x17), mask)
                }
                // nonce > 0x7f：按字节长度写 0x80+|len| + big-endian nonce
                if gt(nonce, 0x7f) {
                    let len := 8
                    for {} shr(len, nonce) { len := add(len, 8) } {}
                    len := shr(3, len)
                    mstore(len, nonce)
                    mstore(0x00, shl(8, account))
                    mstore8(0x1f, add(0x80, len))
                    mstore8(0x0a, 0x94)
                    mstore8(0x09, add(0xd6, len))
                    deployed := and(keccak256(0x09, add(0x17, len)), mask)
                }
                mstore(add(result, mul(i, 0x20)), deployed)
                nonce := add(nonce, 1)
            }
        }
    }

    /// @notice 由 CREATE 推算地址后，批量查询是否已部署合约。
    function getContractsExist(
        bytes25 packed
    ) external view returns (bool[] memory exists){
        address[] memory accounts = getContractFromAccountByNonce(packed);
        uint length = accounts.length;
        exists = new bool[](length);
        assembly {
            for { let i := 0 } lt(i, length) { i := add(i, 1) } {
                let account := mload(add(add(accounts, 0x20), mul(i, 0x20)))
                mstore(add(add(exists, 0x20), mul(i, 0x20)), gt(extcodesize(account), 0))
            }
        }
    }
}
