{-# LANGUAGE RecordWildCards #-}

-- | Define a continuous integration system.
module Development.Bake.Server.Type(
    Server(..), state0,
    Question(..), Answer(..), Ping(..),
    serverConsistent, serverPrune,
    ) where

import Development.Bake.Core.Type
import Development.Bake.Core.Message
import General.Extra
import General.Str
import General.DelayCache
import Data.Time.Clock
import Data.Tuple.Extra
import Data.Maybe
import Control.Monad
import Data.List.Extra
import Data.Map(Map)
import qualified Data.Map as Map


---------------------------------------------------------------------
-- THE DATA TYPE

data Server = Server
    {history :: [(Timestamp, Question, Maybe Answer)]
        -- ^ Questions you have sent to clients, and how they responded (if they have).
    ,updates :: [(Timestamp, State, (State, [Patch]))]
        -- ^ Updates that have been made
    ,pings :: Map Client (Timestamp, Ping)
        -- ^ Latest time of a ping sent by each client
    ,target :: (State, [Patch])
        -- ^ The candidate we are currently aiming to prove
    ,blacklist :: [Test]
        -- ^ Tests that have been blacklisted by hand
    ,paused :: Maybe [(Timestamp, Patch)]
        -- ^ 'Just' if we are paused, and the number of people queued up (reset when target becomes Nothing)
    ,submitted :: [(Timestamp, Patch)]
        -- ^ List of all patches that have been submitted over time
    ,authors :: Map (Maybe Patch) [Author]
        -- ^ Authors associated with each patch (Nothing is the server author)
    ,extra :: DelayCache (Either State Patch) (Str, Str)
        -- ^ Extra information that was computed for each string (cached forever)
    }

state0 :: Server -> State
state0 Server{..} = last $ map (fst . thd3) updates ++ [fst target]


---------------------------------------------------------------------
-- CHECKS ON THE SERVER

-- any question that has been asked of a client who hasn't pinged since the time is thrown away
serverPrune :: UTCTime -> Server -> Server
serverPrune cutoff s = s{history = filter (flip elem clients . qClient . snd3) $ history s}
    where clients = [pClient | (Timestamp t _,Ping{..}) <- Map.elems $ pings s, t >= cutoff]


serverConsistent :: Server -> IO ()
serverConsistent Server{..} = do
    let xs = groupSort $ map (qCandidate . snd3 &&& id) $ filter (isNothing . qTest . snd3) history
    forM_ xs $ \(c,vs) -> do
        case nub $ map (sort . uncurry (++) . aTests) $ filter aSuccess $ mapMaybe thd3 vs of
            a:b:_ -> error $ "Tests don't match for candidate: " ++ show (c,a,b,vs)
            _ -> return ()
