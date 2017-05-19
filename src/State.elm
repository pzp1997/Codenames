module State exposing (..)

import Types exposing (..)
import Sockets
import Vector exposing (..)
import Grid exposing (..)
import RandomList exposing (..)
import WordLists exposing (..)

import Random exposing (Generator, pair)
import Maybe exposing (withDefault, andThen)

-- MODEL

blankBoard : Board
blankBoard = Grid.grid 5 5 dummyCard

newModel : Model
newModel =
    { board = blankBoard
    , turn = Blue
    , hints = False
    , isGameOver = False
    , wordList = NormalWords
    }

init : (Model, Cmd Msg)
init =
     reset newModel

reset : Model -> (Model, Cmd Msg)
reset model =
    {newModel | wordList = model.wordList} ! [randomInitialState model.wordList]



-- UPDATE


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        Click v ->
            click v model ! []
        InitState state ->
            setInitState state model ! []
        SetWordList wl ->
            {model | wordList = wl} ! []
        ToggleHints ->
            {model | hints = not model.hints} ! []
        Reset ->
            reset model
        MouseOverTile b v ->
            {model | board = setMouseOver b v model.board} ! []
        ReceiveMessage mtr ->
            model ! []

click : Vector -> Model -> Model
click v model =
    lookupV v model.board
    |> andThen (\card -> if model.isGameOver then Nothing else Just card)
    |> andThen (\card -> if card.revealed then Nothing else Just card)
    |> Maybe.map (\card -> case card.cardType of
                                Blank -> passTurn model
                                KillWord -> passTurn model
                                Team t -> if t /= model.turn
                                    then passTurn model
                                    else model)
    |> Maybe.map (reveal v)
    |> Maybe.map (endGame)
    |> withDefault model

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

randomInitialState : WordList -> Cmd Msg
randomInitialState wl =
    let
        randomTeam : Generator Team
        randomTeam =
            Random.bool
            |> Random.map (\b -> if b then Blue else Red)

        randomCards : Team -> Generator (List CardType)
        randomCards t =
            shuffle <| cardTypeList t

        randomWords : Generator (List String)
        randomWords =
            shuffle <| getWordList wl

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

setInitState : (Team, List CardType, List String) -> Model -> Model
setInitState (team, cardTypes, cardWords) model =
    model |> setTurn team |> setCardTypes cardTypes |> setCardWords cardWords

reveal : Vector -> Model -> Model
reveal v model =
    let
        setRevealed card = 
            {card | revealed = True}
    in
        {model | board = Grid.mapAtV setRevealed v model.board}

passTurn : Model -> Model
passTurn model =
    {model | turn = otherTeam model.turn}

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

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
    Sockets.subscriptions