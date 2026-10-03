package core

import (
	"github.com/syndtr/goleveldb/leveldb"
	"os"
	"sync"
)

var dbPath = dataLocation()

// Each operation opens the database; serialize access to its file lock.
var leveldbLock sync.Mutex

func dataLocation() string {
	if p := os.Getenv("TROJAN_DATA_DIR"); p != "" {
		return p
	}
	return "/var/lib/trojan-manager"
}

// GetValue 获取leveldb值
func GetValue(key string) (string, error) {
	leveldbLock.Lock()
	defer leveldbLock.Unlock()
	db, err := leveldb.OpenFile(dbPath, nil)
	if err != nil {
		return "", err
	}
	defer db.Close()
	result, err := db.Get([]byte(key), nil)
	if err != nil {
		return "", err
	}
	return string(result), nil
}

// SetValue 设置leveldb值
func SetValue(key string, value string) error {
	leveldbLock.Lock()
	defer leveldbLock.Unlock()
	db, err := leveldb.OpenFile(dbPath, nil)
	if err != nil {
		return err
	}
	defer db.Close()
	return db.Put([]byte(key), []byte(value), nil)
}

// DelValue 删除值
func DelValue(key string) error {
	leveldbLock.Lock()
	defer leveldbLock.Unlock()
	db, err := leveldb.OpenFile(dbPath, nil)
	if err != nil {
		return err
	}
	defer db.Close()
	return db.Delete([]byte(key), nil)
}
