"use client";

import Link from "next/link";
import { useState, useEffect } from "react";
import { useAccount } from "~~/hooks/useAccount";

interface Match {
  id: number;
  teamA: string;
  teamB: string;
  sport: "Basketball" | "Football";
  priceA: number;
  priceB: number;
  status: "PreMatch" | "Halftime" | "Settled";
  firstHalfA?: number;
  firstHalfB?: number;
}

// Mock data - will be replaced with contract reads
const MOCK_MATCHES: Match[] = [
  {
    id: 0,
    teamA: "Lakers",
    teamB: "Warriors",
    sport: "Basketball",
    priceA: 0.52,
    priceB: 0.48,
    status: "PreMatch",
  },
  {
    id: 1,
    teamA: "Bulls",
    teamB: "Celtics",
    sport: "Basketball",
    priceA: 0.45,
    priceB: 0.55,
    status: "Halftime",
    firstHalfA: 52,
    firstHalfB: 58,
  },
  {
    id: 2,
    teamA: "Barcelona",
    teamB: "Real Madrid",
    sport: "Football",
    priceA: 0.60,
    priceB: 0.40,
    status: "PreMatch",
  },
];

const StatusBadge = ({ status }: { status: string }) => {
  const colors = {
    PreMatch: "bg-green-500",
    Halftime: "bg-yellow-500",
    Settled: "bg-gray-500",
  };
  return (
    <span className={`px-2 py-1 rounded-full text-xs text-white ${colors[status as keyof typeof colors]}`}>
      {status === "PreMatch" ? "Live Trading" : status === "Halftime" ? "Halftime Trading" : "Settled"}
    </span>
  );
};

const MatchCard = ({ match }: { match: Match }) => {
  return (
    <div className="bg-base-100 rounded-xl p-6 border border-gradient hover:shadow-lg transition-shadow">
      <div className="flex justify-between items-center mb-4">
        <span className="text-xs text-gray-500">{match.sport}</span>
        <StatusBadge status={match.status} />
      </div>

      <div className="flex justify-between items-center mb-6">
        <div className="text-center flex-1">
          <p className="text-lg font-bold">{match.teamA}</p>
          <p className="text-2xl font-bold text-primary">{(match.priceA * 100).toFixed(0)}%</p>
          {match.firstHalfA !== undefined && (
            <p className="text-sm text-gray-500">1H: {match.firstHalfA}</p>
          )}
        </div>
        <div className="text-center px-4">
          <span className="text-gray-400 text-xl">VS</span>
        </div>
        <div className="text-center flex-1">
          <p className="text-lg font-bold">{match.teamB}</p>
          <p className="text-2xl font-bold text-secondary">{(match.priceB * 100).toFixed(0)}%</p>
          {match.firstHalfB !== undefined && (
            <p className="text-sm text-gray-500">1H: {match.firstHalfB}</p>
          )}
        </div>
      </div>

      <div className="flex gap-2">
        <Link
          href={`/bet/${match.id}?team=A`}
          className="flex-1 btn btn-primary btn-sm"
        >
          Bet {match.teamA}
        </Link>
        <Link
          href={`/bet/${match.id}?team=B`}
          className="flex-1 btn btn-secondary btn-sm"
        >
          Bet {match.teamB}
        </Link>
      </div>

      <div className="mt-4 text-center">
        <Link
          href={`/bet/${match.id}?stealth=true`}
          className="text-xs text-primary hover:underline flex items-center justify-center gap-1"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>
          Private Stealth Bet
        </Link>
      </div>
    </div>
  );
};

const Home = () => {
  const { address, isConnected } = useAccount();
  const [matches, setMatches] = useState<Match[]>(MOCK_MATCHES);

  return (
    <div className="flex flex-col grow">
      {/* Hero Section */}
      <div className="bg-gradient-to-r from-primary/20 to-secondary/20 py-16 px-4">
        <div className="max-w-6xl mx-auto text-center">
          <h1 className="text-5xl font-bold mb-4">
            ZKScore <span className="text-primary">⚡</span> <span className="text-secondary">🏀</span>
          </h1>
          <p className="text-xl text-gray-300 mb-2">
            On-Chain Sports Prediction Markets with Halftime Trading
          </p>
          <p className="text-sm text-gray-500 mb-8">
            Privacy-preserving • No oracles • Verifiable randomness
          </p>

          <div className="flex justify-center gap-4 flex-wrap">
            <div className="bg-base-100 rounded-lg px-4 py-2">
              <span className="text-xs text-gray-500">AMM Model</span>
              <p className="font-bold">CPMM (x*y=k)</p>
            </div>
            <div className="bg-base-100 rounded-lg px-4 py-2">
              <span className="text-xs text-gray-500">Trading Fee</span>
              <p className="font-bold">0.3%</p>
            </div>
            <div className="bg-base-100 rounded-lg px-4 py-2">
              <span className="text-xs text-gray-500">Privacy</span>
              <p className="font-bold">Stealth Addresses</p>
            </div>
          </div>
        </div>
      </div>

      {/* Matches Section */}
      <div className="max-w-6xl mx-auto w-full px-4 py-12">
        <div className="flex justify-between items-center mb-8">
          <h2 className="text-2xl font-bold">Active Markets</h2>
          <Link href="/create" className="btn btn-outline btn-sm">
            + Create Market
          </Link>
        </div>

        {!isConnected ? (
          <div className="text-center py-12 bg-base-100 rounded-xl">
            <p className="text-gray-500 mb-4">Connect your wallet to start betting</p>
            <p className="text-sm text-gray-600">Supports Argent, Braavos, and more</p>
          </div>
        ) : matches.length === 0 ? (
          <div className="text-center py-12 bg-base-100 rounded-xl">
            <p className="text-gray-500">No active markets yet</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {matches.map((match) => (
              <MatchCard key={match.id} match={match} />
            ))}
          </div>
        )}
      </div>

      {/* Features Section */}
      <div className="bg-base-200 py-12 px-4">
        <div className="max-w-6xl mx-auto">
          <h2 className="text-2xl font-bold text-center mb-8">How It Works</h2>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
            <div className="text-center">
              <div className="text-4xl mb-4">1️⃣</div>
              <h3 className="font-bold mb-2">Pre-Match</h3>
              <p className="text-sm text-gray-500">Trade outcome tokens based on your predictions</p>
            </div>
            <div className="text-center">
              <div className="text-4xl mb-4">2️⃣</div>
              <h3 className="font-bold mb-2">First Half</h3>
              <p className="text-sm text-gray-500">Scores revealed via on-chain randomness</p>
            </div>
            <div className="text-center">
              <div className="text-4xl mb-4">3️⃣</div>
              <h3 className="font-bold mb-2">Halftime</h3>
              <p className="text-sm text-gray-500">React to scores! Trade again at new prices</p>
            </div>
            <div className="text-center">
              <div className="text-4xl mb-4">4️⃣</div>
              <h3 className="font-bold mb-2">Settlement</h3>
              <p className="text-sm text-gray-500">Winners redeem tokens at 1:1 ratio</p>
            </div>
          </div>
        </div>
      </div>

      {/* Privacy Section */}
      <div className="py-12 px-4">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-2xl font-bold mb-4">🔒 Privacy-First Betting</h2>
          <p className="text-gray-500 mb-6">
            Use stealth addresses for completely anonymous bets. Your bet amount stays private,
            and only you can claim your winnings.
          </p>
          <Link href="/stealth" className="btn btn-primary">
            Learn About Stealth Betting
          </Link>
        </div>
      </div>
    </div>
  );
};

export default Home;
