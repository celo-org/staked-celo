// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

/**
 * @title ProposalBuilder
 * @notice Accumulates the destination / value / payload triples of a MultiSig proposal.
 * @dev Memory arrays cannot grow, so the builder is created with a capacity and trimmed
 *      to the number of operations that were actually added. It replaces the three
 *      JavaScript arrays the `update:*` tasks pushed onto.
 */
library ProposalBuilder {
    struct Proposal {
        address[] destinations;
        uint256[] values;
        bytes[] payloads;
        uint256 count;
    }

    /// @notice Creates a builder that can hold up to `capacity` operations.
    /// @param capacity The maximum number of operations.
    /// @return proposal The empty builder.
    function init(uint256 capacity) internal pure returns (Proposal memory proposal) {
        proposal.destinations = new address[](capacity);
        proposal.values = new uint256[](capacity);
        proposal.payloads = new bytes[](capacity);
    }

    /// @notice Appends an operation with a zero CELO value.
    /// @param proposal The builder to append to.
    /// @param destination The address the operation targets.
    /// @param payload The calldata of the operation.
    function add(Proposal memory proposal, address destination, bytes memory payload)
        internal
        pure
    {
        require(proposal.count < proposal.destinations.length, "proposal: capacity exceeded");
        proposal.destinations[proposal.count] = destination;
        proposal.values[proposal.count] = 0;
        proposal.payloads[proposal.count] = payload;
        proposal.count++;
    }

    /// @notice The operations added so far, as the three arrays submitProposal takes.
    /// @param proposal The builder to read.
    /// @return destinations The operation destinations.
    /// @return values The operation CELO values.
    /// @return payloads The operation payloads.
    function build(Proposal memory proposal)
        internal
        pure
        returns (address[] memory destinations, uint256[] memory values, bytes[] memory payloads)
    {
        destinations = new address[](proposal.count);
        values = new uint256[](proposal.count);
        payloads = new bytes[](proposal.count);
        for (uint256 i = 0; i < proposal.count; i++) {
            destinations[i] = proposal.destinations[i];
            values[i] = proposal.values[i];
            payloads[i] = proposal.payloads[i];
        }
    }
}
