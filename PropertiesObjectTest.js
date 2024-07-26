var x = new Properties();
x.put('face', 'before');
x.put('zebra', 'after');
x.put('ice', 'date');
x.put('Camel', 'cat');
x.put('delhi', 'jungle');
x.put('Akshay', 'kite');

function sortPropertiesByValue(properties) {
    var sortedProperties = new Properties();
    var entries = [];
    
    // Extract entries from properties
    var keys = properties.keys;
    while (keys.hasMoreElements()) {
        var key = keys.nextElement();
        var value = properties.get(key);
        entries.push({key: key, value: value});
    }
    
    // Sort entries based on values
    entries.sort(function(a, b) {
        return a.value.localeCompare(b.value);
    });
    
    // Put sorted entries back into a new Properties object
    for (var i = 0; i < entries.length; i++) {
        sortedProperties.put(entries[i].key, entries[i].value);
    }
    
    return sortedProperties;
}

var sortedX = sortPropertiesByValue(x);
return sortedX;
