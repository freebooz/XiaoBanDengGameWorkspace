package chinesechess

import (
	"errors"
	"fmt"
)

// Color（阵营颜色）用于区分红方和黑方。
type Color string
const ( Red Color = "red"; Black Color = "black" )

// PieceType（棋子类型）使用英文稳定编码。
type PieceType string
const (
	General PieceType = "general"
	Advisor PieceType = "advisor"
	Elephant PieceType = "elephant"
	Horse PieceType = "horse"
	Chariot PieceType = "chariot"
	Cannon PieceType = "cannon"
	Soldier PieceType = "soldier"
)

// Position（棋盘坐标）：X 为 0~8，Y 为 0~9；红方位于较大的 Y 一侧。
type Position struct { X int `json:"x"`; Y int `json:"y"` }

// Piece（棋子）描述服务端权威棋子状态。
type Piece struct { ID string `json:"id"`; Type PieceType `json:"type"`; Color Color `json:"color"`; Pos Position `json:"pos"`; Alive bool `json:"alive"` }

// Move（走子命令）是客户端提交给规则引擎的操作意图。
type Move struct { PieceID string `json:"piece_id"`; From Position `json:"from"`; To Position `json:"to"` }

// Board（棋盘）保存当前权威棋局状态。
type Board struct { Pieces map[string]*Piece; Turn Color }

// NewInitialBoard（创建初始棋盘）初始化标准中国象棋布局。
func NewInitialBoard() *Board {
	b := &Board{Pieces: map[string]*Piece{}, Turn: Red}
	addBackRank := func(color Color, y int, prefix string) {
		types := []PieceType{Chariot, Horse, Elephant, Advisor, General, Advisor, Elephant, Horse, Chariot}
		for x, t := range types {
			id := fmt.Sprintf("%s_back_%d", prefix, x)
			b.Pieces[id] = &Piece{ID: id, Type: t, Color: color, Pos: Position{X: x, Y: y}, Alive: true}
		}
	}
	addBackRank(Black, 0, "black")
	addBackRank(Red, 9, "red")
	for _, item := range []struct{ color Color; y int; prefix string }{{Black,2,"black_cannon"},{Red,7,"red_cannon"}} {
		for i, x := range []int{1,7} {
			id := fmt.Sprintf("%s_%d", item.prefix, i)
			b.Pieces[id] = &Piece{ID:id, Type:Cannon, Color:item.color, Pos:Position{X:x,Y:item.y}, Alive:true}
		}
	}
	for _, item := range []struct{ color Color; y int; prefix string }{{Black,3,"black_soldier"},{Red,6,"red_soldier"}} {
		for i, x := range []int{0,2,4,6,8} {
			id := fmt.Sprintf("%s_%d", item.prefix, i)
			b.Pieces[id] = &Piece{ID:id, Type:Soldier, Color:item.color, Pos:Position{X:x,Y:item.y}, Alive:true}
		}
	}
	return b
}

// ValidateMove（校验走子）实现一期可执行的基础合法走子规则。
func (b *Board) ValidateMove(m Move) error {
	piece, ok := b.Pieces[m.PieceID]
	if !ok || !piece.Alive { return errors.New("棋子不存在或已经被吃") }
	if piece.Color != b.Turn { return errors.New("当前不是该阵营回合") }
	if piece.Pos != m.From { return errors.New("起点与服务端权威状态不一致") }
	if !inBoard(m.To) || m.From == m.To { return errors.New("目标坐标非法") }
	if target := b.pieceAt(m.To); target != nil && target.Color == piece.Color { return errors.New("不能移动到己方棋子位置") }

	dx, dy := abs(m.To.X-m.From.X), abs(m.To.Y-m.From.Y)
	switch piece.Type {
	case Chariot:
		if dx != 0 && dy != 0 { return errors.New("车只能直线移动") }
		if b.blockersBetween(m.From,m.To) != 0 { return errors.New("车的移动路径被阻挡") }
	case Horse:
		if !((dx==1 && dy==2)||(dx==2 && dy==1)) { return errors.New("马必须走日字") }
		leg := m.From
		if dx==2 { leg.X += sign(m.To.X-m.From.X) } else { leg.Y += sign(m.To.Y-m.From.Y) }
		if b.pieceAt(leg)!=nil { return errors.New("马腿被阻挡") }
	case Soldier:
		if err:=validateSoldier(piece.Color,m.From,m.To); err!=nil { return err }
	case General:
		if dx+dy!=1 || !insidePalace(piece.Color,m.To) { return errors.New("将/帅只能在九宫内横竖移动一格") }
	case Advisor:
		if dx!=1 || dy!=1 || !insidePalace(piece.Color,m.To) { return errors.New("士/仕只能在九宫内斜走一格") }
	case Elephant:
		if dx!=2 || dy!=2 { return errors.New("象/相必须斜走两格") }
		if (piece.Color==Red && m.To.Y<5)||(piece.Color==Black && m.To.Y>4) { return errors.New("象/相不能过河") }
		eye:=Position{X:(m.From.X+m.To.X)/2,Y:(m.From.Y+m.To.Y)/2}
		if b.pieceAt(eye)!=nil { return errors.New("象眼被阻挡") }
	case Cannon:
		if dx!=0 && dy!=0 { return errors.New("炮只能直线移动") }
		blockers:=b.blockersBetween(m.From,m.To)
		target:=b.pieceAt(m.To)
		if target==nil && blockers!=0 { return errors.New("炮不吃子时路径必须为空") }
		if target!=nil && blockers!=1 { return errors.New("炮吃子时必须隔一个棋子") }
	default:
		return errors.New("暂不支持该棋子类型")
	}
	return nil
}

// ApplyMove（应用走子）仅在校验成功后改变权威状态。
func (b *Board) ApplyMove(m Move) error {
	if err:=b.ValidateMove(m); err!=nil { return err }
	if target:=b.pieceAt(m.To); target!=nil { target.Alive=false }
	b.Pieces[m.PieceID].Pos=m.To
	if b.Turn==Red { b.Turn=Black } else { b.Turn=Red }
	return nil
}

func (b *Board) pieceAt(pos Position) *Piece {
	for _,p:=range b.Pieces { if p.Alive && p.Pos==pos { return p } }
	return nil
}
func (b *Board) blockersBetween(a,z Position) int {
	count:=0
	if a.X==z.X {
		step:=sign(z.Y-a.Y)
		for y:=a.Y+step; y!=z.Y; y+=step { if b.pieceAt(Position{X:a.X,Y:y})!=nil { count++ } }
		return count
	}
	if a.Y==z.Y {
		step:=sign(z.X-a.X)
		for x:=a.X+step; x!=z.X; x+=step { if b.pieceAt(Position{X:x,Y:a.Y})!=nil { count++ } }
		return count
	}
	return -1
}
func validateSoldier(color Color, from,to Position) error {
	dx:=abs(to.X-from.X); dy:=to.Y-from.Y
	forward:=-1; crossed:=from.Y<=4
	if color==Black { forward=1; crossed=from.Y>=5 }
	if dy==forward && dx==0 { return nil }
	if crossed && dy==0 && dx==1 { return nil }
	return errors.New("兵/卒只能向前一步，过河后可以横走一步")
}
func insidePalace(color Color,p Position) bool {
	if p.X<3 || p.X>5 { return false }
	if color==Red { return p.Y>=7 && p.Y<=9 }
	return p.Y>=0 && p.Y<=2
}
func inBoard(p Position) bool { return p.X>=0 && p.X<=8 && p.Y>=0 && p.Y<=9 }
func abs(v int) int { if v<0{return -v}; return v }
func sign(v int) int { if v<0{return -1}; if v>0{return 1}; return 0 }