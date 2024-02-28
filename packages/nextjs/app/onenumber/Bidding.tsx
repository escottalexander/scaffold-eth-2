import React from "react";
import { NumberSecret } from "./NumberSecret";
import { GenericContract } from "~~/utils/scaffold-eth/contract";

interface GameProps {
  gameId: number;
  game: bigint[];
  oneNumberContract: GenericContract;
  isBlindedNumberExist: boolean;
}

export const Bidding = ({ gameId, game, oneNumberContract, isBlindedNumberExist }: GameProps) => {
  if (!gameId || !game) {
    return <></>;
  }

  if (isBlindedNumberExist) {
    return <>You have submitted your number!</>;
  }

  return <NumberSecret gameId={gameId} game={game} oneNumberContract={oneNumberContract} isBiddingPhase={true} />;
};
