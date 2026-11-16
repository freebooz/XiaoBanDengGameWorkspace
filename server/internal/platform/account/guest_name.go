package account

import (
	"context"
	"crypto/rand"
	"errors"
	"math/big"

	"github.com/jackc/pgx/v5"
)

var villagePlaces = []string{
	"田埂", "村口", "河湾", "山坳", "寨边", "院坝", "晒谷", "打麦", "赶集", "灶边", "柴门", "竹篱",
	"瓜棚", "豆棚", "牛棚", "塘边", "稻田", "梯田", "谷仓", "磨坊", "菜畦", "菜园", "坡地", "榨坊",
	"桃园", "李园", "梨园", "椒园", "茶园", "果园", "老井", "渡口", "石桥", "湾里", "山脚", "村头",
	"集口", "茶棚", "竹院", "木桥", "水碾", "草垛", "鱼塘", "麦场", "河埠", "碾房", "松坡", "柳堤",
	"秧田", "莲塘", "坡上", "溪边", "竹坞", "石巷", "麦垄", "桑园", "榆荫", "茶坳", "井边", "后山",
}

var villageNicknames = []string{
	"阿牛", "阿旺", "阿福", "阿莲", "阿秀", "阿谷", "阿桂", "阿麦", "阿桃", "阿顺", "阿满", "阿香",
	"幺妹", "幺娃", "幺叔", "幺婶", "二娃", "二丫", "二妞", "二嫂", "三娃", "三妞", "三叔", "三婶",
	"四喜", "四妹", "大娘", "大嫂", "大壮", "大宝", "小满", "小囡", "小杏", "小柱", "小禾", "小穗",
	"麦娃", "麦穗", "豆娃", "豆花", "石娃", "山娃", "春生", "春妮", "冬生", "杏花", "桂香", "桃妹",
	"福生", "福娃", "田娃", "牛娃", "金穗", "银花", "玉兰", "翠花", "兰妹", "老周", "老杨", "老罗",
}

var extendedVillagePlaces, extendedVillageNicknames = buildVillageNamePool()

func buildVillageNamePool() ([]string, []string) {
	const surnames = "王李张刘陈杨黄赵吴周徐孙马朱胡郭何高林罗郑梁谢宋唐许韩邓曹彭曾肖田董袁潘于蒋蔡余杜叶程苏魏吕丁任沈姚卢姜崔钟谭陆汪范金石廖贾夏韦付方白邹孟熊秦邱江尹薛闫段雷侯龙史陶黎贺汤毛郝顾龚邵万钱戴严莫孔向常温康代殷冯伍安乔舒郁兰"
	var places, nicknames []string
	for _, surname := range surnames {
		name := string(surname)
		for _, place := range "庄寨村湾铺桥屯坝" {
			places = append(places, name+string(place))
		}
		nicknames = append(nicknames, "老"+name, "小"+name, "阿"+name)
		for _, title := range "叔婶嫂哥姐伯姨婆爷" {
			nicknames = append(nicknames, name+string(title))
		}
	}
	return places, nicknames
}

func allocateGuestDefaultName(ctx context.Context, tx pgx.Tx) (string, error) {
	places, nicknames := villagePlaces, villageNicknames
	for attempt := range 64 {
		if attempt == 8 {
			places, nicknames = extendedVillagePlaces, extendedVillageNicknames
		}
		choice, err := rand.Int(rand.Reader, big.NewInt(int64(len(places)*len(nicknames))))
		if err != nil {
			return "", err
		}
		index := int(choice.Int64())
		name := places[index/len(nicknames)] + nicknames[index%len(nicknames)]
		reserved, err := reserveGuestDefaultName(ctx, tx, name)
		if err != nil {
			return "", err
		}
		if reserved {
			return name, nil
		}
	}
	return "", errors.New("暂时无法分配不重复的四字游客昵称")
}

func reserveGuestDefaultName(ctx context.Context, tx pgx.Tx, name string) (bool, error) {
	result, err := tx.Exec(ctx, `INSERT INTO guest_default_names(display_name)
		SELECT $1::varchar WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE display_name=$1::varchar)
		ON CONFLICT (display_name) DO NOTHING`, name)
	return result.RowsAffected() == 1, err
}
