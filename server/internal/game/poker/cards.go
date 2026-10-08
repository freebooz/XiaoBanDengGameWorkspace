package poker

// Card face rank 15 represents 2 to match the shared 54-face artwork.
type Card struct { ID int `json:"id"`; Rank int `json:"rank"`; Suit string `json:"suit"` }

func FromID(id int) Card {
	if id<0 || id>=108 { return Card{ID:-1} }
	face:=id%54
	if face==52 { return Card{ID:id,Rank:16,Suit:"small_joker"} }
	if face==53 { return Card{ID:id,Rank:17,Suit:"big_joker"} }
	return Card{ID:id,Rank:face/4+3,Suit:[]string{"spade","heart","club","diamond"}[face%4]}
}

func Deck(copies int) []Card { result:=make([]Card,54*copies);for id:=range result { result[id]=FromID(id) };return result }
