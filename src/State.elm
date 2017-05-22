module State exposing (..)

import Types exposing (..)
import Sockets
import Vector exposing (..)
import Grid exposing (..)
import RandomList exposing (..)
import WordLists exposing (..)

import Random exposing (Generator, pair)
import Maybe exposing (withDefault, andThen)
import Navigation

-- MODEL


init : Navigation.Location -> (Model, Cmd Msg)
init location =
    { newModel | serverAddress = "wss://" ++ location.host } ! []



-- UPDATE


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    let send msgs =
        Sockets.send (model.serverAddress ++ "/submit") msgs
    in
    case msg of
        Send msgs ->
            model ! [send msgs]
        Receive msgs ->
            List.foldr (\x y -> update x <| Tuple.first y) (model ! []) msgs
        Reset ->
            model ! [randomInitialState model.wordList]
        InitState (team, ctl, wl) ->
            let
                msgs =
                    [ NewGame
                    , SetTurn team
                    , SetCardTypes ctl
                    , SetCardWords wl
                    , SetHints False
                    ]
            in
                model ! [send msgs]

        SetClicked v ->
            click v model ! []
        SetCardTypes ctl ->
            setCardTypes ctl model ! []
        SetCardWords wl ->
            setCardWords wl model ! []
        SetTurn team ->
            setTurn team model ! []
        PassTurn ->
            setTurn (otherTeam model.turn) model ! []
        LogPush entry ->
            {model | log = entry::model.log} ! []
        NewGame ->
            model
            |> setUnrevealed
            |> (\m -> {m | hints = False})
            |> (\m -> {m | isGameOver = False})
            |> (\m -> {m | log = []} ! [])

        SetWordList wl ->
            {model | wordList = wl} ! []
        SetHints b ->
            {model | hints = b} ! []
        SetClueBar str ->
            {model | clue = str} ! []
        SetClueNumber str ->
            let
                int =
                    String.toInt str
                    |> Result.withDefault 0
                    |> clamp 0 25
            in
                {model | num = int} ! []
        MouseOverTile b v ->
            {model | board = setMouseOver b v model.board} ! []
        UrlChange location ->
          model ! []


click : Vector -> Model -> Model
click v model =
    lookupV v model.board
    |> andThen (\card -> if model.isGameOver then Nothing else Just card)
    |> andThen (\card -> if card.revealed then Nothing else Just card)
    |> Maybe.map (\card -> logGuess card.word model
        |> maybePassTurn card.cardType
        |> reveal v
        |> endGame)
    |> withDefault model

reveal : Vector -> Model -> Model
reveal v model =
    let
        setRevealed card =
            {card | revealed = True}
    in
        {model | board = Grid.mapAtV setRevealed v model.board}

maybePassTurn : CardType -> Model -> Model
maybePassTurn ct model =
    case ct of
        Blank -> passTurn model
        KillWord -> passTurn model
        Team t -> if t /= model.turn
            then passTurn model
            else model

passTurn : Model -> Model
passTurn model =
    {model | turn = otherTeam model.turn}

logGuess : String -> Model -> Model
logGuess str model =
    let
        update str (a,b,c,words) =
            (a,b,c, str::words)
    in
        model.log
        |> List.indexedMap (\i entry -> if i==0 then update str entry else entry)
        |> (\lg -> {model | log = lg})



setMouseOver : Bool -> Vector -> Board -> Board
setMouseOver b v board =
    let
        withMouseOver b card =
            {card | mouseOver = b}
    in
        lookupV v board
        |> Maybe.map (\card -> withMouseOver b card)
        |> Maybe.map (\card -> setV v card board)
        |> withDefault board

randomInitialState : WordList -> Cmd Msg
randomInitialState wl =
    let
        cardTypeList : Team -> List CardType
        cardTypeList activeTeam =
            List.repeat 9 (Team activeTeam)
            ++ List.repeat 8 (Team <| otherTeam activeTeam)
            ++ List.repeat 7 Blank
            ++ List.singleton KillWord

        getWordList : WordList -> List String
        getWordList wl =
            case wl of
                EasyWords -> WordLists.easy_words
                NormalWords -> WordLists.words
                OriginalWords -> WordLists.original

        randomTeam : Generator Team
        randomTeam =
            Random.bool
            |> Random.map (\b -> if b then Blue else Red)

        randomCards : Team -> Generator (List CardType)
        randomCards t =
            shuffle <| cardTypeList t

        randomWords : Generator (List String)
        randomWords =
             Random.map (List.take 25) <| shuffle <| getWordList wl

    in
        randomTeam
        |> Random.andThen (\team -> pair (constant team) (randomCards team))
        |> Random.map2 (\ls (t, lct) -> (,,) t lct ls) randomWords
        |> Random.generate InitState


setTurn : Team -> Model -> Model
setTurn team model =
    {model | turn = team}

setCardTypes : List CardType -> Model -> Model
setCardTypes cardTypes model =
    let
        index v =
            (getX v) + (5 * getY v)
        setOwner v card =
            {card | cardType = withDefault Blank <| flip get cardTypes <| index v}
    in
        {model | board = Grid.indexedMap setOwner model.board}

setCardWords : List String -> Model -> Model
setCardWords cardWords model =
    let
        index v =
            (getX v) + (5 * getY v)
        setWord v card =
            {card | word = withDefault "ERROR" <| flip get cardWords <| index v}
    in
        {model | board = Grid.indexedMap setWord model.board}

setUnrevealed : Model -> Model
setUnrevealed model =
    let
        board
            = model.board
        newBoard =
            Grid.map (\card -> {card | revealed = False}) board
    in
        {model | board = newBoard}

cardsRemaining : Board -> CardType -> Int
cardsRemaining board cardType =
    let
        doesCount card =
            card.cardType == cardType && card.revealed == False
        doesCount_ v =
            lookupV v board
            |> Maybe.map doesCount
            |> withDefault False
    in
        Grid.allVectors board
        |> List.filter doesCount_
        |> List.length

endGame : Model -> Model
endGame model =
    let
        noneRemaining : CardType -> Bool
        noneRemaining = ((==) 0) << cardsRemaining model.board
    in
        if List.any noneRemaining [Team Blue, Team Red, KillWord]
            then {model | isGameOver = True}
            else model

setGameOver : Bool -> Model -> Model
setGameOver b model =
    {model | isGameOver = b}

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
    Sockets.subscriptions (model.serverAddress ++ "/receive")
