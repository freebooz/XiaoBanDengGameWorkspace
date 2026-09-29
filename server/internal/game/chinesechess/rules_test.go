package chinesechess

import "testing"

func TestHorseCanMoveFromInitialPosition(t *testing.T) {
	board:=NewInitialBoard()
	move:=Move{PieceID:"red_back_1",From:Position{X:1,Y:9},To:Position{X:2,Y:7}}
	if err:=board.ValidateMove(move); err!=nil { t.Fatalf("红马初始应可走到(2,7): %v",err) }
}

func TestSoldierCanMoveForward(t *testing.T) {
	board:=NewInitialBoard()
	move:=Move{PieceID:"red_soldier_0",From:Position{X:0,Y:6},To:Position{X:0,Y:5}}
	if err:=board.ValidateMove(move); err!=nil { t.Fatalf("红兵向前一步应合法: %v",err) }
}